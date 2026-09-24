#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    fs,
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager, State};
use uuid::Uuid;

const ENGINE_SCRIPT: &str = include_str!("../../powershell/AutopilotGdap.Engine.psm1");
const WORKER_SCRIPT: &str = include_str!("../../powershell/AutopilotGdap.Worker.ps1");
const PUBLIC_CLIENT_ID: &str = "6a87f18c-ab0a-4ef9-bb1c-587ae884b8e0";

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct FrontendRequest {
    request_id: Option<String>,
    action: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct WorkerEvent {
    kind: String,
    request_id: String,
    event: String,
    payload: Value,
}

struct WorkerProcess {
    stdin: Mutex<ChildStdin>,
    child: Mutex<Child>,
    busy: Arc<AtomicBool>,
}

struct AppState {
    worker: Mutex<Option<WorkerProcess>>,
}

impl AppState {
    fn submit(&self, app: &AppHandle, request: &FrontendRequest) -> Result<String, String> {
        validate_request(request)?;
        let request_id = request
            .request_id
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| Uuid::new_v4().to_string());

        let mut worker_guard = self
            .worker
            .lock()
            .map_err(|_| "De PowerShell-worker kon niet worden vergrendeld.")?;
        if worker_guard.is_none() {
            *worker_guard = Some(WorkerProcess::spawn(app)?);
        }
        let worker = worker_guard
            .as_ref()
            .ok_or_else(|| "De PowerShell-worker kon niet worden gestart.".to_string())?;

        if worker.busy.swap(true, Ordering::SeqCst) {
            return Err(
                "Er wordt al een Autopilot-actie uitgevoerd. Wacht tot deze is afgerond."
                    .to_string(),
            );
        }

        let mut command = request.clone();
        command.request_id = Some(request_id.clone());
        let serialized = serde_json::to_string(&command)
            .map_err(|error| format!("De backendactie kon niet worden voorbereid: {error}"))?;

        let write_result = worker
            .stdin
            .lock()
            .map_err(|_| "De invoer van de PowerShell-worker is niet beschikbaar.".to_string())
            .and_then(|mut stdin| {
                stdin.write_all(serialized.as_bytes()).map_err(|error| {
                    format!("De backendactie kon niet worden verstuurd: {error}")
                })?;
                stdin.write_all(b"\n").map_err(|error| {
                    format!("De backendactie kon niet worden verstuurd: {error}")
                })?;
                stdin
                    .flush()
                    .map_err(|error| format!("De backendactie kon niet worden verstuurd: {error}"))
            });

        if let Err(error) = write_result {
            worker.busy.store(false, Ordering::SeqCst);
            return Err(error);
        }
        Ok(request_id)
    }
}

impl WorkerProcess {
    fn spawn(app: &AppHandle) -> Result<Self, String> {
        let runtime_dir = write_runtime_scripts(app)?;
        let worker_path = runtime_dir.join("AutopilotGdap.Worker.ps1");
        let engine_path = runtime_dir.join("AutopilotGdap.Engine.psm1");
        let executable = if cfg!(target_os = "windows") {
            "powershell.exe"
        } else {
            "pwsh"
        };

        let mut command = Command::new(executable);
        command
            .arg("-NoLogo")
            .arg("-NoProfile")
            .arg("-NonInteractive")
            .arg("-ExecutionPolicy")
            .arg("Bypass")
            .arg("-File")
            .arg(&worker_path)
            .arg("-EnginePath")
            .arg(&engine_path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x0800_0000;
            let parent_window_handle = app
                .get_webview_window("main")
                .and_then(|window| window.hwnd().ok())
                .map(|window_handle| (window_handle.0 as usize).to_string())
                .ok_or_else(|| {
                    "Het Tauri-venster kon niet aan Windows Web Account Manager worden gekoppeld."
                        .to_string()
                })?;
            command.env("CAPTURETECH_PARENT_HWND", parent_window_handle);
            command.creation_flags(CREATE_NO_WINDOW);
        }

        let mut child = command
            .spawn()
            .map_err(|error| format!("PowerShell kon niet worden gestart: {error}"))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "De PowerShell-worker heeft geen invoerkanaal.".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "De PowerShell-worker heeft geen uitvoerkanaal.".to_string())?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| "De PowerShell-worker heeft geen foutkanaal.".to_string())?;
        let busy = Arc::new(AtomicBool::new(false));

        spawn_stdout_reader(app.clone(), stdout, Arc::clone(&busy));
        spawn_stderr_reader(app.clone(), stderr);

        Ok(Self {
            stdin: Mutex::new(stdin),
            child: Mutex::new(child),
            busy,
        })
    }
}

impl Drop for WorkerProcess {
    fn drop(&mut self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
        }
    }
}

fn spawn_stdout_reader(
    app: AppHandle,
    stdout: impl std::io::Read + Send + 'static,
    busy: Arc<AtomicBool>,
) {
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            match serde_json::from_str::<Value>(&line) {
                Ok(message) => {
                    if message.get("kind").and_then(Value::as_str) == Some("result") {
                        busy.store(false, Ordering::SeqCst);
                    }
                    let _ = app.emit("worker-event", message);
                }
                Err(_) => {
                    let _ = app.emit(
                        "worker-event",
                        WorkerEvent {
                            kind: "event".to_string(),
                            request_id: String::new(),
                            event: "log".to_string(),
                            payload: json!({
                                "message": line,
                                "level": "warning",
                                "technical": true
                            }),
                        },
                    );
                }
            }
        }
        busy.store(false, Ordering::SeqCst);
    });
}

fn spawn_stderr_reader(app: AppHandle, stderr: impl std::io::Read + Send + 'static) {
    thread::spawn(move || {
        for line in BufReader::new(stderr).lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            let _ = app.emit(
                "worker-event",
                WorkerEvent {
                    kind: "event".to_string(),
                    request_id: String::new(),
                    event: "log".to_string(),
                    payload: json!({
                        "message": line,
                        "level": "warning",
                        "technical": true
                    }),
                },
            );
        }
    });
}

fn write_runtime_scripts(app: &AppHandle) -> Result<PathBuf, String> {
    let directory = app
        .path()
        .app_local_data_dir()
        .map_err(|error| format!("Het lokale apppad kon niet worden bepaald: {error}"))?
        .join("runtime");
    fs::create_dir_all(&directory)
        .map_err(|error| format!("De runtime-map kon niet worden aangemaakt: {error}"))?;
    write_if_changed(&directory.join("AutopilotGdap.Engine.psm1"), ENGINE_SCRIPT)?;
    write_if_changed(&directory.join("AutopilotGdap.Worker.ps1"), WORKER_SCRIPT)?;
    Ok(directory)
}

fn write_if_changed(path: &Path, contents: &str) -> Result<(), String> {
    if fs::read_to_string(path).ok().as_deref() == Some(contents) {
        return Ok(());
    }
    fs::write(path, contents)
        .map_err(|error| format!("Runtimebestand kon niet worden geschreven: {error}"))
}

fn validate_request(request: &FrontendRequest) -> Result<(), String> {
    let object = request
        .payload
        .as_object()
        .ok_or_else(|| "De backendactie bevat geen geldig gegevensobject.".to_string())?;
    match request.action.as_str() {
        "preflight" | "loginPartner" | "loadCustomers" | "loadProfiles" | "resetSession"
        | "restartDevice" => {
            if !object.is_empty() {
                return Err("Deze backendactie accepteert geen extra parameters.".to_string());
            }
        }
        "connectCustomer" => {
            validate_allowed_fields(object, &["tenantId"])?;
            let tenant_id = object
                .get("tenantId")
                .and_then(Value::as_str)
                .ok_or_else(|| "Een klanttenant-ID is verplicht.".to_string())?;
            Uuid::parse_str(tenant_id).map_err(|_| "De klanttenant-ID is ongeldig.".to_string())?;
        }
        "registerDevice" => {
            validate_allowed_fields(
                object,
                &["profileId", "staticGroupId", "hostname", "verbose"],
            )?;
            let profile_id = object
                .get("profileId")
                .and_then(Value::as_str)
                .ok_or_else(|| "Een Autopilot-profiel is verplicht.".to_string())?;
            if profile_id.trim().is_empty() || profile_id.len() > 128 {
                return Err("Het Autopilot-profiel is ongeldig.".to_string());
            }
            if let Some(hostname) = object.get("hostname").and_then(Value::as_str) {
                if hostname.len() > 15
                    || hostname.is_empty()
                    || !hostname
                        .chars()
                        .all(|character| character.is_ascii_alphanumeric() || character == '-')
                {
                    return Err("De apparaatnaam mag maximaal 15 tekens bevatten: letters, cijfers en streepjes.".to_string());
                }
            }
            if let Some(group_id) = object.get("staticGroupId").and_then(Value::as_str) {
                if group_id.trim().is_empty() || group_id.len() > 128 {
                    return Err("De gekozen statische groep is ongeldig.".to_string());
                }
            }
            if !object.get("verbose").is_some_and(Value::is_boolean) {
                return Err("De technische-uitvoerinstelling ontbreekt.".to_string());
            }
        }
        _ => return Err("Deze backendactie is niet toegestaan.".to_string()),
    }
    Ok(())
}

fn validate_allowed_fields(
    object: &serde_json::Map<String, Value>,
    allowed: &[&str],
) -> Result<(), String> {
    let unexpected = object
        .keys()
        .filter(|key| !allowed.iter().any(|allowed_key| key == allowed_key))
        .map(|key| key.as_str())
        .collect::<Vec<_>>();
    if unexpected.is_empty() {
        return Ok(());
    }
    Err(format!(
        "Deze backendactie bevat niet-toegestane parameter(s): {}.",
        unexpected.join(", ")
    ))
}

fn validate_customer_tenant(tenant_id: &str) -> Result<(), String> {
    Uuid::parse_str(tenant_id).map_err(|_| "De klanttenant-ID is ongeldig.".to_string())?;
    Ok(())
}

fn browser_cancellation_path() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("TEMP").map(PathBuf::from))
        .unwrap_or_else(std::env::temp_dir);
    base.join("CaptureTech")
        .join("AutopilotGDAP")
        .join("browser-auth.cancel")
}

fn cancel_browser_authorization() -> Result<(), String> {
    let path = browser_cancellation_path();
    let parent = path
        .parent()
        .ok_or_else(|| "Het pad voor de browseraanmelding is ongeldig.".to_string())?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("De browseraanmelding kon niet worden onderbroken: {error}"))?;
    fs::write(&path, b"customer-consent")
        .map_err(|error| format!("De browseraanmelding kon niet worden onderbroken: {error}"))
}

#[cfg(target_os = "windows")]
fn shell_execute(operation: &str, target: &std::ffi::OsStr) -> Result<(), String> {
    use std::{
        ffi::{c_void, OsStr},
        os::windows::ffi::OsStrExt,
        ptr,
    };

    #[link(name = "shell32")]
    extern "system" {
        fn ShellExecuteW(
            hwnd: *mut c_void,
            operation: *const u16,
            file: *const u16,
            parameters: *const u16,
            directory: *const u16,
            show_command: i32,
        ) -> isize;
    }

    fn wide(value: &OsStr) -> Vec<u16> {
        value.encode_wide().chain(std::iter::once(0)).collect()
    }

    let operation = wide(OsStr::new(operation));
    let target = wide(target);
    let result = unsafe {
        ShellExecuteW(
            ptr::null_mut(),
            operation.as_ptr(),
            target.as_ptr(),
            ptr::null(),
            ptr::null(),
            1,
        )
    };
    if result <= 32 {
        return Err(format!(
            "Windows kon de gevraagde actie niet starten (ShellExecute-code {result})."
        ));
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn open_in_default_browser(url: &str) -> Result<(), String> {
    shell_execute("open", std::ffi::OsStr::new(url))
}

#[cfg(not(target_os = "windows"))]
fn open_in_default_browser(_url: &str) -> Result<(), String> {
    Err("Klantinstelling openen wordt alleen door de Windows-app ondersteund.".to_string())
}

#[cfg(target_os = "windows")]
fn relaunch_as_administrator(app: AppHandle) -> Result<(), String> {
    use std::time::Duration;

    let executable = std::env::current_exe()
        .map_err(|error| format!("Het uitvoerbare bestand kon niet worden bepaald: {error}"))?;
    shell_execute("runas", executable.as_os_str())?;

    // Give the invoke response time to reach the frontend before closing the
    // non-elevated instance. The newly started process gets its own UAC token.
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(250));
        app.exit(0);
    });
    Ok(())
}

#[cfg(not(target_os = "windows"))]
fn relaunch_as_administrator(_app: AppHandle) -> Result<(), String> {
    Err(
        "Opnieuw starten als administrator wordt alleen door de Windows-app ondersteund."
            .to_string(),
    )
}

#[tauri::command]
fn worker_request(
    app: AppHandle,
    state: State<'_, AppState>,
    request: FrontendRequest,
) -> Result<String, String> {
    state.submit(&app, &request)
}

#[tauri::command]
fn restart_as_administrator(app: AppHandle) -> Result<(), String> {
    relaunch_as_administrator(app)
}

#[tauri::command]
fn open_customer_consent(tenant_id: String, cancel_pending_login: bool) -> Result<(), String> {
    validate_customer_tenant(&tenant_id)?;
    let consent_url = format!(
        "https://login.microsoftonline.com/{tenant_id}/adminconsent?client_id={PUBLIC_CLIENT_ID}&redirect_uri=http%3A%2F%2Flocalhost"
    );
    open_in_default_browser(&consent_url)?;
    if cancel_pending_login {
        cancel_browser_authorization()?;
    }
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .manage(AppState {
            worker: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![
            worker_request,
            restart_as_administrator,
            open_customer_consent
        ])
        .run(tauri::generate_context!())
        .expect("CaptureTech Autopilot GDAP kon niet worden gestart");
}

#[cfg(test)]
mod tests {
    use super::{validate_customer_tenant, validate_request, FrontendRequest};
    use serde_json::json;

    #[test]
    fn accepts_a_valid_customer_tenant_id() {
        assert!(validate_customer_tenant("609ba4a6-ac45-4a08-b108-54f46f635e6d").is_ok());
    }

    #[test]
    fn rejects_an_invalid_customer_tenant_id() {
        assert!(validate_customer_tenant("not-a-tenant").is_err());
    }

    #[test]
    fn accepts_reset_session_without_payload() {
        let request = FrontendRequest {
            request_id: None,
            action: "resetSession".to_string(),
            payload: json!({}),
        };
        assert!(validate_request(&request).is_ok());
    }

    #[test]
    fn rejects_reset_session_with_payload() {
        let request = FrontendRequest {
            request_id: None,
            action: "resetSession".to_string(),
            payload: json!({ "tenantId": "609ba4a6-ac45-4a08-b108-54f46f635e6d" }),
        };
        assert!(validate_request(&request).is_err());
    }
}
