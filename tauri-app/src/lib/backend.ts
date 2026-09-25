import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { Customer, Profile, WorkerEvent, WorkerRequest } from "../types";

const isTauri = () => "__TAURI_INTERNALS__" in window;

const demoCustomers: Customer[] = [
  {
    tenantId: "609ba4a6-ac45-4a08-b108-54f46f635e6d",
    customerName: "Hanab Energy Solutions",
    tenantDomain: "otworkstation.nl",
    displayName: "Hanab Energy Solutions [otworkstation.nl]",
  },
  {
    tenantId: "8c880615-4fe9-443a-b92d-bb8b55af9b10",
    customerName: "CaptureTech Demo",
    tenantDomain: "capturetech-demo.nl",
    displayName: "CaptureTech Demo [capturetech-demo.nl]",
  },
];

const demoProfiles: Profile[] = [
  {
    profileId: "demo-profile-1",
    displayName: "OT 1.8 Autopilot profile",
    groups: [
      {
        id: "dynamic-vm",
        name: "OTWerkplekVM",
        type: "Dynamisch",
        isDynamic: true,
        isExclusion: false,
        securityEnabled: true,
        membershipRule: '(device.devicePhysicalIds -any _ -eq "[OrderID]:OTWerkplekVM")',
        membershipRuleProcessingState: "On",
      },
      {
        id: "static-shared",
        name: "OTWerkplekShared",
        type: "Statisch",
        isDynamic: false,
        isExclusion: false,
        securityEnabled: true,
      },
      {
        id: "static-workplace",
        name: "OTWerkplek",
        type: "Statisch",
        isDynamic: false,
        isExclusion: false,
        securityEnabled: true,
      },
    ],
    groupCandidates: [
      {
        id: "static-shared",
        name: "OTWerkplekShared",
        displayName: "OTWerkplekShared - direct statisch",
        source: "Direct toegewezen statische groep",
      },
      {
        id: "static-workplace",
        name: "OTWerkplek",
        displayName: "OTWerkplek - direct statisch",
        source: "Direct toegewezen statische groep",
      },
    ],
    orderIdGroupTag: "OTWerkplekVM",
    orderIdGroupTagStatus: "resolved",
    orderIdGroupTagCandidates: ["OTWerkplekVM"],
  },
  {
    profileId: "demo-profile-2",
    displayName: "Standaard Autopilot-profiel zonder groep",
    groups: [],
    groupCandidates: [],
    orderIdGroupTagStatus: "none",
  },
  {
    profileId: "demo-profile-3",
    displayName: "Autopilot-profiel met één statische groep",
    groups: [
      {
        id: "static-laptops",
        name: "CT-Autopilot-Laptops",
        type: "Statisch",
        isDynamic: false,
        isExclusion: false,
        securityEnabled: true,
      },
    ],
    groupCandidates: [
      {
        id: "static-laptops",
        name: "CT-Autopilot-Laptops",
        displayName: "CT-Autopilot-Laptops - direct statisch",
        source: "Direct toegewezen statische groep",
      },
    ],
    orderIdGroupTagStatus: "none",
  },
  {
    profileId: "demo-profile-4",
    displayName: "Autopilot-profiel met dynamische groep",
    groups: [
      {
        id: "dynamic-tagged",
        name: "CT-Autopilot-Tag-Blue",
        type: "Dynamisch",
        isDynamic: true,
        isExclusion: false,
        securityEnabled: true,
        membershipRule: '(device.devicePhysicalIds -any _ -eq "[OrderID]:CT-Blue")',
        membershipRuleProcessingState: "On",
      },
    ],
    groupCandidates: [],
    orderIdGroupTag: "CT-Blue",
    orderIdGroupTagStatus: "resolved",
    orderIdGroupTagCandidates: ["CT-Blue"],
  },
];

export const isDesktopApp = isTauri;

export async function subscribeWorkerEvents(handler: (event: WorkerEvent) => void): Promise<UnlistenFn | null> {
  if (!isTauri()) return null;
  return listen<WorkerEvent>("worker-event", (event) => handler(event.payload));
}

export async function sendWorkerRequest(request: WorkerRequest): Promise<string> {
  if (isTauri()) {
    return invoke<string>("worker_request", { request });
  }
  return request.requestId ?? crypto.randomUUID();
}

export async function restartAsAdministrator(): Promise<void> {
  if (!isTauri()) return;
  await invoke<void>("restart_as_administrator");
}

export async function openCustomerConsent(tenantId: string, cancelPendingLogin: boolean): Promise<void> {
  if (!isTauri()) return;
  await invoke<void>("open_customer_consent", { tenantId, cancelPendingLogin });
}

export function getDemoResult(request: WorkerRequest): unknown {
  switch (request.action) {
    case "preflight":
      return {
        isAdministrator: true,
        powershellVersion: "5.1",
        graphModuleInstalled: true,
        authMode: "wam",
        isOobe: false,
        wamAvailable: true,
      };
    case "loginPartner":
      return {
        tenantId: "26aaae92-5737-48a2-b00c-27aff5b013e7",
        account: "it-hulp@capturetech.example",
        authMode: "wam",
        isOobe: false,
        customers: demoCustomers,
        customerCount: demoCustomers.length,
      };
    case "loadCustomers":
      return { customers: demoCustomers, customerCount: demoCustomers.length };
    case "loadProfiles":
      return { profiles: demoProfiles };
    case "connectCustomer":
      return {
        tenantId: request.payload.tenantId,
        account: "it-hulp@capturetech.example",
        authMode: "wam",
        customerAuthMode: "wam",
      };
    case "resetSession":
      return { authMode: "wam", sessionReset: true };
    case "registerDevice": {
      const profile = demoProfiles.find((entry) => entry.profileId === request.payload.profileId);
      const staticGroup = profile?.groupCandidates.find((candidate) => candidate.id === request.payload.staticGroupId);
      return {
        serialNumber: "DEMO-AP-0001",
        staticGroupName: staticGroup?.name,
        orderIdGroupTag: profile?.orderIdGroupTag,
        dynamicGroups: profile?.groups.filter((group) => group.isDynamic) ?? [],
        importCompleted: true,
        assigned: true,
      };
    }
    default:
      return {};
  }
}

export function getDemoLogs(action: WorkerRequest): Array<Pick<WorkerEvent, "event" | "payload">> {
  const base = { event: "log" as const, payload: { level: "info" as const, technical: false } };
  if (action.action === "loginPartner") {
    return [{ ...base, payload: { ...base.payload, message: "Windows opent de accountkiezer voor het IT-Hulp-account." } }];
  }
  if (action.action === "connectCustomer") {
    return [{ ...base, payload: { ...base.payload, message: "Verbonden met de geselecteerde klanttenant." } }];
  }
  if (action.action === "registerDevice") {
    return [
      { ...base, payload: { ...base.payload, message: "Hardwarehash verzameld." } },
      { ...base, payload: { ...base.payload, message: "Autopilot-apparaat geïmporteerd." } },
      { ...base, payload: { ...base.payload, message: "Autopilot-profiel toegewezen." } },
    ];
  }
  return [];
}
