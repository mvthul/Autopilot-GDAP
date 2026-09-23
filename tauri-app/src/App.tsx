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
  Search,
  ShieldCheck,
  TerminalSquare,
  UserRoundCheck,
} from "lucide-react";
import {
  getDemoLogs,
  getDemoResult,
  isDesktopApp,
  sendWorkerRequest,
  subscribeWorkerEvents,
} from "./lib/backend";
import type {
  Customer,
  GroupCandidate,
  LogEntry,
  PreflightResult,
  Profile,
  RegisterResult,
  WorkerAction,
  WorkerEvent,
  WorkerRequest,
  WorkflowStep,
} from "./types";

type Pending = { id: string; action: WorkerRequest["action"] };

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

export function App() {
  const [step, setStep] = useState<WorkflowStep>("login");
  const [preflight, setPreflight] = useState<PreflightResult | null>(null);
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
  const [nextAction, setNextAction] = useState<WorkerRequest | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [error, setError] = useState("");
  const [registration, setRegistration] = useState<RegisterResult | null>(null);
  const [showTechnicalLog, setShowTechnicalLog] = useState(false);
  const [confirmRestart, setConfirmRestart] = useState(false);

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
        case "loginPartner":
          appendLog("IT-Hulp-account aangemeld. Partner Center-klanten worden opgehaald.", "success");
          setNextAction({ action: "loadCustomers", payload: {} });
          return;
        case "loadCustomers": {
          const loaded = (data as { customers?: Customer[] }).customers ?? [];
          setCustomers(loaded);
          setStep("customer");
          appendLog(`${loaded.length} klant${loaded.length === 1 ? "" : "en"} geladen vanuit Partner Center.`, "success");
          return;
        }
        case "connectCustomer":
          appendLog("Klantcontext is geverifieerd. Autopilot-profielen worden geladen.", "success");
          setNextAction({ action: "loadProfiles", payload: {} });
          return;
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
        const message = event.error ?? "De bewerking is niet voltooid.";
        setError(message);
        appendLog(message, "error");
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
      const active = { id: requestId, action: request.action } as Pending;
      pendingRef.current = active;
      setPending(active);

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
  const hasSessionDetails = Boolean(selectedCustomer || selectedProfile || registration || busy || visibleLogs.length > 0);

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
            <span>Deze app moet als administrator worden gestart om hardwaregegevens uit te lezen en een herstart uit te voeren.</span>
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
                <p className="lead">Gebruik je normale werkaccount. De browser opent veilig voor Microsoft Graph en Partner Center.</p>
                <div className="feature-row">
                  <div className="feature-icon"><LockKeyhole size={22} /></div>
                  <div><strong>Geen device code</strong><span>De normale browseraanmelding wordt gebruikt.</span></div>
                </div>
                <div className="feature-row">
                  <div className="feature-icon"><UserRoundCheck size={22} /></div>
                  <div><strong>GDAP en PIM blijven leidend</strong><span>De tool gebruikt alleen jouw actieve delegated rechten.</span></div>
                </div>
                <button className="button primary" type="button" disabled={busy} onClick={() => void dispatch({ action: "loginPartner", payload: {} })}>
                  {busy ? <LoaderCircle className="spin" size={18} /> : <ArrowRight size={18} />}
                  {busy ? "Aanmelding voorbereiden…" : "Aanmelden met IT-Hulp-account"}
                </button>
                <p className="hint">Bij de eerste keer kan Partner Center ook om browserconsent vragen.</p>
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
                      onClick={() => setSelectedCustomerId(customer.tenantId)}
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
                  {busy ? "Klantcontext openen…" : "Verbind met klanttenant"}
                </button>
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
                <div><dt>Klant</dt><dd>{selectedCustomer?.customerName ?? "Nog niet gekozen"}</dd></div>
                <div><dt>Profiel</dt><dd>{selectedProfile?.displayName ?? "Nog niet gekozen"}</dd></div>
                <div><dt>Groep</dt><dd>{selectedCandidate?.name ?? (selectedProfile?.groupCandidates.length === 0 ? "Automatisch" : "Nog niet gekozen")}</dd></div>
                <div><dt>Hostname</dt><dd>{hostname || "Automatisch"}</dd></div>
              </dl>
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
    </main>
  );
}
