import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  AlertCircle,
  ArrowRight,
  Check,
  ChevronDown,
  CircleHelp,
  Computer,
  FileText,
  LoaderCircle,
  LockKeyhole,
  Power,
  RefreshCw,
  Search,
  ShieldCheck,
  TerminalSquare,
  UserRoundCheck,
} from "lucide-react";
import {
  getDemoLogs,
  getDemoResult,
  isDesktopApp,
  openCustomerConsent,
  restartAsAdministrator,
  sendWorkerRequest,
  subscribeWorkerEvents,
} from "./lib/backend";
import type {
  Customer,
  CustomerConnectionResult,
  GroupCandidate,
  LoginResult,
  LogEntry,
  PreflightResult,
  Profile,
  RegisterResult,
  WorkerAction,
  WorkerEvent,
  WorkerRequest,
  WorkflowStep,
  AuthMode,
  CustomerAuthMode,
} from "./types";

type Pending = { id: string; action: WorkerRequest["action"]; customer?: Customer };

type CustomerConsentDialog = {
  customer: Customer;
  setupStarted: boolean;
};

const steps: Array<{ id: WorkflowStep; number: string; title: string; caption: string }> = [
  { id: "login", number: "01", title: "Aanmelden", caption: "IT-Hulp-account" },
  { id: "customer", number: "02", title: "Klant kiezen", caption: "Partner Center" },
  { id: "configure", number: "03", title: "Profiel kiezen", caption: "Autopilot-configuratie" },
  { id: "register", number: "04", title: "Registreren", caption: "Import & assignment" },
];

const workflowOrder: WorkflowStep[] = ["login", "customer", "configure", "register", "complete"];

function isStepComplete(current: WorkflowStep, step: WorkflowStep) {
  return workflowOrder.indexOf(current) > workflowOrder.indexOf(step);
}

function getGroupSummary(profile: Profile) {
  if (profile.groups.length === 0) {
    return "Geen toegewezen groep";
  }
  return profile.groups.map((group) => `${group.name} [${group.type}]`).join(" · ");
}

function getGroupDecision(profile: Profile | undefined, selectedCandidate?: GroupCandidate) {
  if (!profile || profile.groups.length === 0) {
    return "Autopilot koppelt het profiel automatisch. Er wordt geen groep handmatig aangepast.";
  }
  if (profile.groupCandidates.length === 0) {
    return "Er is geen geschikte statische groep. Dynamische groepen worden uitsluitend door Entra beoordeeld.";
  }
  if (profile.groupCandidates.length === 1) {
    return `De statische groep “${profile.groupCandidates[0].name}” wordt na import automatisch verwerkt.`;
  }
  if (!selectedCandidate) {
    return "Kies de statische groep die na import moet worden verwerkt.";
  }
  return `Na import wordt “${selectedCandidate.name}” als statische groepsactie uitgevoerd.`;
}

function getOrderIdGroupTagDecision(profile: Profile | undefined) {
  if (!profile) return null;
  if (profile.orderIdGroupTag) {
    return `Dynamische OrderID-regel herkend: Group Tag “${profile.orderIdGroupTag}” wordt tijdens registratie automatisch ingesteld.`;
  }
  if (profile.orderIdGroupTagStatus === "ambiguous") {
    const tags = profile.orderIdGroupTagCandidates?.join(", ") || "onbekend";
    return `Meerdere verschillende OrderID-tags gevonden (${tags}). Er wordt uit veiligheid geen Group Tag automatisch ingesteld.`;
  }
  return null;
}

export function App() {
  const [step, setStep] = useState<WorkflowStep>("login");
  const [preflight, setPreflight] = useState<PreflightResult | null>(null);
  const [sessionAccount, setSessionAccount] = useState("");
  const [sessionAuthMode, setSessionAuthMode] = useState<AuthMode | null>(null);
  const [customerAuthMode, setCustomerAuthMode] = useState<CustomerAuthMode | null>(null);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [customerSearch, setCustomerSearch] = useState("");
  const [selectedCustomerId, setSelectedCustomerId] = useState("");
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [selectedProfileId, setSelectedProfileId] = useState("");
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [hostname, setHostname] = useState("");
  const [verbose, setVerbose] = useState(false);
  const [pending, setPending] = useState<Pending | null>(null);
  const pendingRef = useRef<Pending | null>(null);
  const customersRef = useRef<Customer[]>([]);
  const [nextAction, setNextAction] = useState<WorkerRequest | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [error, setError] = useState("");
  const [registration, setRegistration] = useState<RegisterResult | null>(null);
  const [showTechnicalLog, setShowTechnicalLog] = useState(false);
  const [confirmRestart, setConfirmRestart] = useState(false);
  const [elevating, setElevating] = useState(false);
  const [customerConsentDialog, setCustomerConsentDialog] = useState<CustomerConsentDialog | null>(null);
  const [startingCustomerConsent, setStartingCustomerConsent] = useState(false);

  const selectedCustomer = customers.find((customer) => customer.tenantId === selectedCustomerId);
  const selectedProfile = profiles.find((profile) => profile.profileId === selectedProfileId);
  const selectedCandidate = selectedProfile?.groupCandidates.find((candidate) => candidate.id === selectedGroupId);
  const busy = pending !== null;

  const filteredCustomers = useMemo(() => {
    const query = customerSearch.trim().toLocaleLowerCase("nl-NL");
    if (!query) return customers;
    return customers.filter((customer) =>
      [customer.customerName, customer.displayName, customer.tenantDomain, customer.tenantId]
        .join(" ")
        .toLocaleLowerCase("nl-NL")
        .includes(query),
    );
  }, [customerSearch, customers]);

  const appendLog = useCallback((message: string, level: LogEntry["level"] = "info", technical = false) => {
    if (!message.trim()) return;
    setLogs((current) => [
      ...current,
      { id: crypto.randomUUID(), at: new Date().toLocaleTimeString("nl-NL"), message, level, technical },
    ]);
  }, []);

  const handleResult = useCallback(
    (action: WorkerRequest["action"], data: unknown) => {
      switch (action) {
        case "preflight":
          setPreflight(data as PreflightResult);
          return;
        case "loginPartner": {
          const result = data as LoginResult;
          setSessionAccount(result.account);
          setSessionAuthMode(result.authMode);
          const loaded = customersRef.current.length > 0 ? customersRef.current : result.customers ?? [];
          const customerCount = result.customerCount ?? loaded.length;
          customersRef.current = loaded;
          setCustomers(loaded);
          setStep("customer");
          appendLog(
            result.authMode === "wam"
              ? `${customerCount} klant${customerCount === 1 ? "" : "en"} zijn via Windows en Partner Center geladen.`
              : `${customerCount} klant${customerCount === 1 ? "" : "en"} zijn via de OOBE-browser en Partner Center geladen.`,
            "success",
          );
          return;
        }
        case "loadCustomers": {
          const result = data as { customers?: Customer[]; customerCount?: number };
          const loaded = customersRef.current.length > 0 ? customersRef.current : result.customers ?? [];
          const customerCount = result.customerCount ?? loaded.length;
          customersRef.current = loaded;
          setCustomers(loaded);
          setStep("customer");
          appendLog(`${customerCount} klant${customerCount === 1 ? "" : "en"} geladen vanuit Partner Center.`, "success");
          return;
        }
        case "connectCustomer": {
          const result = data as CustomerConnectionResult;
          setCustomerConsentDialog(null);
          setSessionAccount((current) => result.account || current);
          setSessionAuthMode(result.authMode);
          setCustomerAuthMode(result.customerAuthMode ?? (result.authMode === "browserOobe" ? "browserOobe" : "wam"));
          appendLog("Klantcontext is geverifieerd. Autopilot-profielen worden geladen.", "success");
          setNextAction({ action: "loadProfiles", payload: {} });
          return;
        }
        case "loadProfiles": {
          const loaded = (data as { profiles?: Profile[] }).profiles ?? [];
          setProfiles(loaded);
          setSelectedProfileId(loaded[0]?.profileId ?? "");
          setSelectedGroupId(loaded[0]?.groupCandidates.length === 1 ? loaded[0].groupCandidates[0].id : "");
          setStep("configure");
          appendLog(`${loaded.length} Autopilot-profiel${loaded.length === 1 ? "" : "en"} geladen.`, "success");
          return;
        }
        case "registerDevice": {
          const result = data as RegisterResult;
          setRegistration(result);
          setStep("complete");
          appendLog("Autopilot-import en profieltoewijzing zijn succesvol afgerond.", "success");
          return;
        }
        case "resetSession":
          setStep("login");
          setCustomers([]);
          setCustomerSearch("");
          setSelectedCustomerId("");
          setProfiles([]);
          setSelectedProfileId("");
          setSelectedGroupId("");
          setHostname("");
          setRegistration(null);
          setCustomerConsentDialog(null);
          setSessionAccount("");
          setSessionAuthMode(null);
          setCustomerAuthMode(null);
          setNextAction(null);
          setLogs([]);
          appendLog("De appsessie is gewist. Kies opnieuw het gewenste IT-Hulp-account.", "info");
          return;
        case "restartDevice":
          appendLog("De computer wordt opnieuw gestart.", "success");
          return;
      }
    },
    [appendLog],
  );

  const handleWorkerEvent = useCallback(
    (event: WorkerEvent) => {
      if (event.kind === "event") {
        if (event.event === "customers") {
          const active = pendingRef.current;
          if (!active || active.id !== event.requestId || (active.action !== "loginPartner" && active.action !== "loadCustomers")) {
            return;
          }
          const incoming = event.payload?.customers ?? [];
          if (incoming.length === 0) return;
          const byTenantId = new Map(customersRef.current.map((customer) => [customer.tenantId, customer]));
          for (const customer of incoming) byTenantId.set(customer.tenantId, customer);
          const merged = Array.from(byTenantId.values());
          customersRef.current = merged;
          setCustomers(merged);
          return;
        }
        const message = event.payload?.message;
        if (message) appendLog(message, event.payload?.level ?? "info", Boolean(event.payload?.technical));
        if (event.payload?.step) setStep(event.payload.step);
        return;
      }

      const active = pendingRef.current;
      if (!active || active.id !== event.requestId) return;
      pendingRef.current = null;
      setPending(null);
      if (!event.ok) {
        const workerError = event.error ?? { code: "operationFailed" as const, message: "De bewerking is niet voltooid." };
        if (active.action === "connectCustomer" && active.customer && workerError.code === "customerConsentRequired") {
          const customer = active.customer;
          setCustomerConsentDialog((current) => ({
            customer,
            setupStarted: current?.customer.tenantId === customer.tenantId && current?.setupStarted === true,
          }));
          appendLog("De klant-app heeft eenmalige autorisatie nodig voordat de GDAP-verbinding kan worden geopend.", "warning");
          return;
        }
        setError(workerError.message);
        appendLog(workerError.message, workerError.code === "authCancelled" ? "warning" : "error");
        if (workerError.details && workerError.details !== workerError.message) {
          appendLog(workerError.details, "error", true);
        }
        return;
      }
      handleResult(active.action, event.data);
    },
    [appendLog, handleResult],
  );

  const dispatch = useCallback(
    async (request: WorkerRequest) => {
      if (pendingRef.current) return;
      setError("");
      const requestId = crypto.randomUUID();
      const requestWithId = { ...request, requestId } as WorkerRequest;
      const active = {
        id: requestId,
        action: request.action,
        customer: request.action === "connectCustomer"
          ? customersRef.current.find((customer) => customer.tenantId === request.payload.tenantId)
          : undefined,
      } as Pending;
      pendingRef.current = active;
      setPending(active);

      if (request.action === "loginPartner" || request.action === "loadCustomers") {
        customersRef.current = [];
        setCustomers([]);
      }

      try {
        if (isDesktopApp()) {
          const returnedId = await sendWorkerRequest(requestWithId);
          if (returnedId !== requestId) {
            pendingRef.current = { ...active, id: returnedId };
            setPending({ ...active, id: returnedId });
          }
          return;
        }

        for (const log of getDemoLogs(requestWithId)) {
          if (log.payload?.message) appendLog(log.payload.message, log.payload.level, Boolean(log.payload.technical));
        }
        window.setTimeout(() => {
          pendingRef.current = null;
          setPending(null);
          handleResult(active.action, getDemoResult(requestWithId));
        }, request.action === "registerDevice" ? 1400 : 450);
      } catch (caught) {
        const message = caught instanceof Error ? caught.message : String(caught);
        pendingRef.current = null;
        setPending(null);
        setError(message);
        appendLog(message, "error");
      }
    },
    [appendLog, handleResult],
  );

  useEffect(() => {
    customersRef.current = customers;
  }, [customers]);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    let disposed = false;
    void (async () => {
      unlisten = await subscribeWorkerEvents(handleWorkerEvent);
      if (!disposed) await dispatch({ action: "preflight", payload: {} });
    })();
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [dispatch, handleWorkerEvent]);

  useEffect(() => {
    if (!nextAction || busy) return;
    setNextAction(null);
    void dispatch(nextAction);
  }, [busy, dispatch, nextAction]);

  const selectProfile = (profileId: string) => {
    const profile = profiles.find((entry) => entry.profileId === profileId);
    setSelectedProfileId(profileId);
    setSelectedGroupId(profile?.groupCandidates.length === 1 ? profile.groupCandidates[0].id : "");
  };

  const connectCustomer = () => {
    if (!selectedCustomer) return;
    void dispatch({ action: "connectCustomer", payload: { tenantId: selectedCustomer.tenantId } });
  };

  const resetSession = () => {
    if (busy) return;
    void dispatch({ action: "resetSession", payload: {} });
  };

  const requestElevation = async () => {
    setError("");
    setElevating(true);
    try {
      await restartAsAdministrator();
      appendLog("Windows vraagt om bevestiging om de app als administrator opnieuw te starten.", "info");
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught);
      setError(message);
      appendLog(message, "error");
    } finally {
      setElevating(false);
    }
  };

  const startCustomerSetup = async () => {
    const customer = customerConsentDialog?.customer;
    if (!customer) return;
    setError("");
    setStartingCustomerConsent(true);
    try {
      await openCustomerConsent(customer.tenantId, false);
      appendLog(`De klantinstelling voor ${customer.customerName} is in de browser geopend.`, "info");
      setCustomerConsentDialog((current) => current && ({
        ...current,
        setupStarted: true,
      }));
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught);
      setError(message);
      appendLog(message, "error");
    } finally {
      setStartingCustomerConsent(false);
    }
  };

  const registerDevice = () => {
    if (!selectedProfile) return;
    if (selectedProfile.groupCandidates.length > 1 && !selectedGroupId) {
      setError("Kies eerst de statische groep die na import moet worden verwerkt.");
      return;
    }
    setStep("register");
    setLogs([]);
    void dispatch({
      action: "registerDevice",
      payload: {
        profileId: selectedProfile.profileId,
        staticGroupId: selectedGroupId || undefined,
        hostname: hostname.trim() || undefined,
        verbose,
      },
    });
  };

  const visibleLogs = logs.filter((entry) => showTechnicalLog || !entry.technical);
  const canRegister = Boolean(selectedProfile) && (!selectedProfile || selectedProfile.groupCandidates.length < 2 || Boolean(selectedGroupId));
  const hasSessionDetails = Boolean(sessionAccount || selectedCustomer || selectedProfile || registration || busy || visibleLogs.length > 0);
  const usingOobeBrowser = (sessionAuthMode ?? preflight?.authMode) === "browserOobe";
  const canStartLogin = !preflight || preflight.authMode === "browserOobe" || preflight.wamAvailable;
  const customerBusyLabel = pending?.action === "loginPartner" || pending?.action === "loadCustomers"
    ? "Klantenlijst laden…"
    : "Klantcontext openen…";

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <img src="/capturetech-logo-black.svg" alt="CaptureTech" />
          <span>Autopilot GDAP</span>
        </div>

        <div className="sidebar-copy">
          <p className="eyebrow">Device provisioning</p>
          <h1>Windows klaarzetten, zonder omwegen.</h1>
          <p>Registreer een apparaat veilig in de juiste klanttenant en laat Autopilot het vervolg doen.</p>
        </div>

        <nav className="step-nav" aria-label="Registratiestappen">
          {steps.map((item) => {
            const active = step === item.id || (step === "complete" && item.id === "register");
            const complete = isStepComplete(step, item.id) || step === "complete";
            return (
              <div className={`step-link ${active ? "active" : ""} ${complete ? "complete" : ""}`} key={item.id}>
                <span className="step-index">{complete ? <Check size={15} strokeWidth={3} /> : item.number}</span>
                <span>
                  <strong>{item.title}</strong>
                  <small>{item.caption}</small>
                </span>
              </div>
            );
          })}
        </nav>

        <div className="sidebar-footer">
          <ShieldCheck size={18} />
          <span>Delegated access via GDAP</span>
        </div>
      </aside>

      <section className="workspace">
        <header className="topbar">
          <div className="topbar-brand">
            <img src="/capturetech-logo-black.svg" alt="CaptureTech" />
            <div>
              <p className="eyebrow">Device provisioning</p>
              <p className="topbar-title">Autopilot Deployment Tool</p>
            </div>
          </div>
          <div className={`environment ${isDesktopApp() ? "desktop" : "demo"}`}>
            <span className="environment-dot" />
            {isDesktopApp() ? "Windows app" : "Design preview"}
          </div>
        </header>

        {!preflight?.isAdministrator && preflight && (
          <div className="notice warning">
            <AlertCircle size={20} />
            <div className="notice-copy">
              <span>Deze app moet als administrator worden gestart om hardwaregegevens uit te lezen en een herstart uit te voeren.</span>
              <button className="notice-action" type="button" disabled={elevating} onClick={() => void requestElevation()}>
                {elevating ? <LoaderCircle className="spin" size={15} /> : <ShieldCheck size={15} />}
                {elevating ? "UAC openen…" : "Start opnieuw als administrator"}
              </button>
            </div>
          </div>
        )}

        {preflight?.authMode === "wam" && !preflight.wamAvailable && (
          <div className="notice error">
            <AlertCircle size={20} />
            <span>Windows Web Account Manager is niet beschikbaar voor dit venster. Start de app opnieuw in een normale interactieve Windows-sessie.</span>
          </div>
        )}

        {error && (
          <div className="notice error">
            <AlertCircle size={20} />
            <span>{error}</span>
            <button type="button" className="notice-close" onClick={() => setError("")} aria-label="Melding sluiten">×</button>
          </div>
        )}

        <div className="content-grid">
          <section className="content-card main-card">
            {step === "login" && (
              <>
                <p className="eyebrow">Stap 1 van 4</p>
                <h2>Meld aan met je IT-Hulp-account</h2>
                <p className="lead">
                  {usingOobeBrowser
                    ? "Windows Setup is actief. De browser gebruikt veilig dezelfde Microsoft SSO-sessie voor Graph en Partner Center."
                    : "Windows toont één accountkiezer voor de partner-sessie. Partner Center gebruikt die sessie stil; alleen wanneer een klant een GDAP-browsercontext vereist, opent browser-SSO automatisch voor die klant."}
                </p>
                <div className="feature-row">
                  <div className="feature-icon"><LockKeyhole size={22} /></div>
                  <div>
                    <strong>{usingOobeBrowser ? "Geen device code" : "Native Windows-aanmelding"}</strong>
                    <span>{usingOobeBrowser ? "De normale browser-SSO wordt alleen tijdens OOBE gebruikt." : "Windows Web Account Manager opent boven deze app en keert hierna direct terug."}</span>
                  </div>
                </div>
                <div className="feature-row">
                  <div className="feature-icon"><UserRoundCheck size={22} /></div>
                  <div><strong>GDAP en PIM blijven leidend</strong><span>De tool gebruikt alleen jouw actieve delegated rechten. Een eventuele browser-SSO voor een klant wordt daarna ook tijdens registratie hergebruikt.</span></div>
                </div>
                <button className="button primary" type="button" disabled={busy || !canStartLogin} onClick={() => void dispatch({ action: "loginPartner", payload: {} })}>
                  {busy ? <LoaderCircle className="spin" size={18} /> : <ArrowRight size={18} />}
                  {busy ? "Aanmelding voorbereiden…" : usingOobeBrowser ? "Aanmelden met IT-Hulp-account" : "Kies IT-Hulp-account"}
                </button>
                <p className="hint">{usingOobeBrowser ? "Bij eerste gebruik kan Partner Center in de browser consent vragen." : "Bij Conditional Access, MFA of een klantconsent kan Windows of de browser aanvullende verificatie vragen."}</p>
              </>
            )}

            {step === "customer" && (
              <>
                <p className="eyebrow">Stap 2 van 4</p>
                <h2>Kies de klanttenant</h2>
                <p className="lead">Zoek op klantnaam, domein of tenant-ID. De lijst komt rechtstreeks uit Partner Center.</p>
                <label className="field-label" htmlFor="customer-search">Klant zoeken</label>
                <div className="search-input">
                  <Search size={19} />
                  <input id="customer-search" value={customerSearch} onChange={(event) => setCustomerSearch(event.target.value)} placeholder="Bijvoorbeeld Hanab" autoFocus />
                </div>
                <div className="customer-list" role="listbox" aria-label="Klanttenants">
                  {filteredCustomers.map((customer) => (
                    <button
                      type="button"
                      role="option"
                      aria-selected={selectedCustomerId === customer.tenantId}
                      className={`customer-option ${selectedCustomerId === customer.tenantId ? "selected" : ""}`}
                      onClick={() => {
                        setSelectedCustomerId(customer.tenantId);
                        setCustomerAuthMode(null);
                      }}
                      key={customer.tenantId}
                    >
                      <span className="customer-name">{customer.customerName}</span>
                      <span>{customer.tenantDomain}</span>
                      <code>{customer.tenantId}</code>
                    </button>
                  ))}
                  {filteredCustomers.length === 0 && <p className="empty-state">Geen klant gevonden voor deze zoekopdracht.</p>}
                </div>
                <button className="button primary" type="button" disabled={!selectedCustomer || busy} onClick={connectCustomer}>
                  {busy ? <LoaderCircle className="spin" size={18} /> : <ArrowRight size={18} />}
                  {busy ? customerBusyLabel : "Verbind met klanttenant"}
                </button>
                <button
                  className="customer-setup-link"
                  type="button"
                  disabled={!selectedCustomer || busy}
                  onClick={() => selectedCustomer && setCustomerConsentDialog({ customer: selectedCustomer, setupStarted: false })}
                >
                  <FileText size={16} />
                  App-toegang voor deze klant instellen
                </button>
                <p className="hint">Alleen nodig als de klanttenant de CaptureTech Autopilot GDAP-app nog niet eenmalig heeft geautoriseerd.</p>
              </>
            )}

            {step === "configure" && selectedCustomer && (
              <>
                <p className="eyebrow">Stap 3 van 4</p>
                <h2>Kies profiel en groepsactie</h2>
                <p className="lead">De app analyseert de profieltoewijzingen voordat het apparaat wordt geïmporteerd.</p>
                <div className="selected-customer">
                  <div className="customer-mark"><Computer size={20} /></div>
                  <div><span>Klanttenant</span><strong>{selectedCustomer.customerName}</strong><small>{selectedCustomer.tenantDomain}</small></div>
                  <button type="button" className="text-button" onClick={() => setStep("customer")}>Wijzigen</button>
                </div>

                <label className="field-label" htmlFor="profile-select">Autopilot-profiel</label>
                <div className="select-wrap">
                  <select id="profile-select" value={selectedProfileId} onChange={(event) => selectProfile(event.target.value)}>
                    {profiles.map((profile) => <option value={profile.profileId} key={profile.profileId}>{profile.displayName}</option>)}
                  </select>
                  <ChevronDown size={18} />
                </div>
                {selectedProfile && <p className="selection-caption">{getGroupSummary(selectedProfile)}</p>}

                {selectedProfile && (
                  <div className="group-panel">
                    <div className="group-panel-header"><FileText size={18} /><strong>Profieltoewijzingen</strong></div>
                    {selectedProfile.groups.length === 0 ? (
                      <p>Geen toegewezen groep. Autopilot bepaalt de configuratie automatisch.</p>
                    ) : (
                      <div className="group-list">
                        {selectedProfile.groups.map((group) => (
                          <div className="group-row" key={group.id}>
                            <span className={`badge ${group.isExclusion ? "exclusion" : group.isDynamic ? "dynamic" : "static"}`}>{group.isExclusion ? "Uitsluiting" : group.type}</span>
                            <div>
                              <strong>{group.name}</strong>
                              <small>{group.securityEnabled ? "Beveiligingsgroep" : "Geen beveiligingsgroep"}{group.mailEnabled ? " · E-mail ingeschakeld" : ""}{group.hasNested ? " · Nested relatie" : ""}{group.isDynamic && group.membershipRuleProcessingState ? ` · Regelstatus: ${group.membershipRuleProcessingState}` : ""}</small>
                              {group.isDynamic && group.membershipRule && <code>{group.membershipRule}</code>}
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                    <p className="group-decision">{getGroupDecision(selectedProfile, selectedCandidate)}</p>
                    {getOrderIdGroupTagDecision(selectedProfile) && <p className="group-decision">{getOrderIdGroupTagDecision(selectedProfile)}</p>}
                  </div>
                )}

                {selectedProfile && selectedProfile.groupCandidates.length > 1 && (
                  <>
                    <label className="field-label" htmlFor="group-select">Statische groep voor handmatige toevoeging</label>
                    <div className="select-wrap">
                      <select id="group-select" value={selectedGroupId} onChange={(event) => setSelectedGroupId(event.target.value)}>
                        <option value="">Kies een groep…</option>
                        {selectedProfile.groupCandidates.map((candidate) => <option value={candidate.id} key={candidate.id}>{candidate.displayName}</option>)}
                      </select>
                      <ChevronDown size={18} />
                    </div>
                  </>
                )}

                <label className="field-label" htmlFor="hostname">Apparaatnaam <span>optioneel</span></label>
                <input id="hostname" className="text-input" value={hostname} onChange={(event) => setHostname(event.target.value)} placeholder="Bijvoorbeeld CT-LAP-001" maxLength={15} />

                <label className="checkbox-row">
                  <input type="checkbox" checked={verbose} onChange={(event) => setVerbose(event.target.checked)} />
                  <span>Technische Graph-uitvoer opnemen in het log</span>
                  <span title="GET/POST-aanroepen en modulemeldingen zijn alleen nodig voor diagnose."><CircleHelp size={16} /></span>
                </label>

                <button className="button primary" type="button" disabled={!canRegister || busy} onClick={registerDevice}>
                  <ArrowRight size={18} />
                  Registreer apparaat
                </button>
              </>
            )}

            {(step === "register" || step === "complete") && (
              <>
                <p className="eyebrow">Stap 4 van 4</p>
                <h2>{step === "complete" ? "Apparaat is gereed" : "Apparaat registreren"}</h2>
                <p className="lead">{step === "complete" ? "De Autopilot-import en profieltoewijzing zijn voltooid." : "De hardwarehash wordt opgehaald en veilig in de geselecteerde klanttenant geregistreerd."}</p>

                <div className={`registration-status ${step === "complete" ? "success" : "running"}`}>
                  {step === "complete" ? <Check size={24} /> : <LoaderCircle className="spin" size={24} />}
                  <div>
                    <strong>{step === "complete" ? "Autopilot registratie voltooid" : "Registratie wordt uitgevoerd"}</strong>
                    <span>{step === "complete" ? `Serienummer: ${registration?.serialNumber ?? "onbekend"}` : "Dit kan enkele minuten duren. Sluit de app niet."}</span>
                  </div>
                </div>

                {registration?.staticGroupName && <div className="result-row"><Check size={18} /><span>Toegevoegd aan statische groep <strong>{registration.staticGroupName}</strong></span></div>}
                {registration?.orderIdGroupTag && <div className="result-row neutral"><ShieldCheck size={18} /><span>Group Tag <strong>{registration.orderIdGroupTag}</strong> is ingesteld voor de dynamische Entra-regel.</span></div>}
                {(registration?.dynamicGroups ?? []).map((group) => <div className="result-row neutral" key={group.id}><ShieldCheck size={18} /><span><strong>{group.name}</strong> wordt automatisch door Entra beoordeeld.</span></div>)}

                {step === "complete" && (
                  <div className="restart-card">
                    <div><Power size={21} /><span><strong>Herstart de computer</strong><small>Start Windows Setup opnieuw om de Autopilot-flow te vervolgen.</small></span></div>
                    <button className="button outline" type="button" disabled={busy} onClick={() => setConfirmRestart(true)}>Herstart computer</button>
                  </div>
                )}
              </>
            )}
          </section>

          <aside className={`status-column ${hasSessionDetails ? "" : "status-idle"}`}>
            <section className="content-card device-card">
              <p className="eyebrow">Sessie</p>
              <h3>Registratieoverzicht</h3>
              <dl>
                <div><dt>IT-Hulp-account</dt><dd>{sessionAccount || "Nog niet aangemeld"}</dd></div>
                <div><dt>Aanmelding</dt><dd>{sessionAuthMode === "wam" ? "Windows WAM" : sessionAuthMode === "browserOobe" ? "OOBE-browser" : "Nog niet gestart"}</dd></div>
                <div><dt>Klant</dt><dd>{selectedCustomer?.customerName ?? "Nog niet gekozen"}</dd></div>
                <div><dt>Klantcontext</dt><dd>{customerAuthMode === "browserSsoFallback" ? "Browser-SSO (GDAP)" : customerAuthMode === "browserOobe" ? "OOBE-browser" : customerAuthMode === "wam" ? "Windows WAM" : "Nog niet geopend"}</dd></div>
                <div><dt>Profiel</dt><dd>{selectedProfile?.displayName ?? "Nog niet gekozen"}</dd></div>
                <div><dt>Groep</dt><dd>{selectedCandidate?.name ?? (selectedProfile?.groupCandidates.length === 0 ? "Automatisch" : "Nog niet gekozen")}</dd></div>
                {selectedProfile && <div><dt>Group Tag</dt><dd>{selectedProfile.orderIdGroupTag ?? (selectedProfile.orderIdGroupTagStatus === "ambiguous" ? "Meerdere tags; niet automatisch ingesteld" : "Niet van toepassing")}</dd></div>}
                <div><dt>Hostname</dt><dd>{hostname || "Automatisch"}</dd></div>
              </dl>
              {sessionAccount && (
                <button className="session-reset" type="button" disabled={busy} onClick={resetSession}>
                  <RefreshCw size={15} /> Wissel account
                </button>
              )}
            </section>

            <section className={`content-card log-card ${visibleLogs.length === 0 && !busy ? "empty-log-card" : ""}`}>
              <div className="log-header">
                <div><p className="eyebrow">Live status</p><h3>Uitvoer</h3></div>
                {busy && <LoaderCircle className="spin accent" size={18} />}
              </div>
              <div className="log-list" aria-live="polite">
                {visibleLogs.length === 0 ? <p className="empty-log">Voortgang en resultaten verschijnen hier.</p> : visibleLogs.map((entry) => (
                  <div className={`log-entry ${entry.level}`} key={entry.id}>
                    <time>{entry.at}</time><span>{entry.message}</span>
                  </div>
                ))}
              </div>
              <button type="button" className="technical-toggle" onClick={() => setShowTechnicalLog((current) => !current)}>
                <TerminalSquare size={16} />
                {showTechnicalLog ? "Verberg technische uitvoer" : "Toon technische uitvoer"}
              </button>
            </section>
          </aside>
        </div>
      </section>

      {confirmRestart && (
        <div className="dialog-backdrop" role="presentation">
          <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="restart-heading">
            <div className="dialog-icon"><Power size={24} /></div>
            <h2 id="restart-heading">Computer herstarten?</h2>
            <p>De computer wordt direct opnieuw gestart. Sla eventueel openstaand werk eerst op.</p>
            <div className="dialog-actions">
              <button className="button ghost" type="button" onClick={() => setConfirmRestart(false)}>Annuleren</button>
              <button className="button primary" type="button" onClick={() => { setConfirmRestart(false); void dispatch({ action: "restartDevice", payload: {} }); }}>Ja, herstart</button>
            </div>
          </section>
        </div>
      )}

      {customerConsentDialog && (
        <div className="dialog-backdrop" role="presentation">
          <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="customer-consent-heading">
            <div className="dialog-icon"><FileText size={24} /></div>
            <h2 id="customer-consent-heading">{customerConsentDialog.setupStarted ? "Klantinstelling geopend" : "Klant-app instellen"}</h2>
            {customerConsentDialog.setupStarted ? (
              <p>De tenant-specifieke admin-consentpagina is in de standaardbrowser geopend. Laat een Global Administrator van {customerConsentDialog.customer.customerName} de gevraagde machtigingen accepteren. Kom daarna hier terug en verbind opnieuw.</p>
            ) : (
              <p>De klanttenant {customerConsentDialog.customer.customerName} heeft de CaptureTech Autopilot GDAP-app nog niet geautoriseerd. Laat een Global Administrator van de klanttenant de eenmalige consent verlenen.</p>
            )}
            <div className="dialog-actions">
              <button className="button ghost" type="button" onClick={() => setCustomerConsentDialog(null)}>Sluiten</button>
              {customerConsentDialog.setupStarted ? (
                <button
                  className="button outline"
                  type="button"
                  disabled={busy}
                  onClick={() => {
                    setCustomerConsentDialog(null);
                    connectCustomer();
                  }}
                >
                  Opnieuw verbinden
                </button>
              ) : (
                <button className="button primary" type="button" disabled={startingCustomerConsent} onClick={() => void startCustomerSetup()}>
                  {startingCustomerConsent ? <LoaderCircle className="spin" size={18} /> : <ArrowRight size={18} />}
                  {startingCustomerConsent ? "Browser openen…" : "Klantinstelling starten"}
                </button>
              )}
            </div>
          </section>
        </div>
      )}
    </main>
  );
}
