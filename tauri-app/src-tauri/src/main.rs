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
            return Err("Er wordt al een Autopilot-actie uitgevoerd. Wacht tot deze is afgerond.".to_string());
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
                stdin
                    .write_all(serialized.as_bytes())
                    .map_err(|error| format!("De backendactie kon niet worden verstuurd: {error}"))?;
                stdin
                    .write_all(b"\n")
                    .map_err(|error| format!("De backendactie kon niet worden verstuurd: {error}"))?;
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
    fs::write(path, contents).map_err(|error| format!("Runtimebestand kon niet worden geschreven: {error}"))
}

fn validate_request(request: &FrontendRequest) -> Result<(), String> {
    let object = request
        .payload
        .as_object()
        .ok_or_else(|| "De backendactie bevat geen geldig gegevensobject.".to_string())?;
    match request.action.as_str() {
        "preflight" | "loginPartner" | "loadCustomers" | "loadProfiles" | "restartDevice" => {
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
            validate_allowed_fields(object, &["profileId", "staticGroupId", "hostname", "verbose"])?;
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

#[tauri::command]
fn worker_request(
    app: AppHandle,
    state: State<'_, AppState>,
    request: FrontendRequest,
) -> Result<String, String> {
    state.submit(&app, &request)
}

fn main() {
    tauri::Builder::default()
        .manage(AppState {
            worker: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![worker_request])
        .run(tauri::generate_context!())
        .expect("CaptureTech Autopilot GDAP kon niet worden gestart");
}
