export type WorkflowStep = "login" | "customer" | "configure" | "register" | "complete";

export type LogLevel = "info" | "success" | "warning" | "error";

export type AuthMode = "wam" | "browserOobe";

/** Authentication source for the active customer Graph context. */
export type CustomerAuthMode = "wam" | "browserSsoFallback" | "browserOobe";

export type WorkerErrorCode =
  | "customerConsentRequired"
  | "partnerCenterConsentRequired"
  | "gdapPimDenied"
  | "wamUnavailable"
  | "authCancelled"
  | "authenticationRequired"
  | "operationFailed";

export interface WorkerError {
  code: WorkerErrorCode;
  message: string;
  details?: string;
}

export interface Customer {
  tenantId: string;
  customerName: string;
  tenantDomain: string;
  displayName: string;
}

export interface GroupInfo {
  id: string;
  name: string;
  type: "Statisch" | "Dynamisch";
  isDynamic: boolean;
  isExclusion: boolean;
  membershipRule?: string;
  membershipRuleProcessingState?: string;
  hasNested?: boolean;
  securityEnabled?: boolean;
  mailEnabled?: boolean;
}

export interface GroupCandidate {
  id: string;
  name: string;
  displayName: string;
  source: string;
}

export interface Profile {
  profileId: string;
  displayName: string;
  groups: GroupInfo[];
  groupCandidates: GroupCandidate[];
  /** A unique [OrderID]:tag inferred from assigned dynamic Entra groups. */
  orderIdGroupTag?: string;
  orderIdGroupTagStatus?: "none" | "resolved" | "ambiguous";
  orderIdGroupTagCandidates?: string[];
}

export interface PreflightResult {
  isAdministrator: boolean;
  powershellVersion: string;
  graphModuleInstalled: boolean;
  authMode: AuthMode;
  isOobe: boolean;
  wamAvailable: boolean;
}

export interface LoginResult {
  tenantId: string;
  account: string;
  authMode: AuthMode;
  isOobe: boolean;
  /** Demo and older workers can still return a complete list. */
  customers?: Customer[];
  /** Production workers transfer the list through small `customers` events. */
  customerCount?: number;
}

export interface CustomerConnectionResult {
  tenantId: string;
  account: string;
  authMode: AuthMode;
  customerAuthMode?: CustomerAuthMode;
}

export interface RegisterResult {
  serialNumber: string;
  staticGroupName?: string;
  orderIdGroupTag?: string;
  dynamicGroups: GroupInfo[];
  importCompleted: boolean;
  assigned: boolean;
}

export type WorkerAction =
  | { action: "preflight"; payload: Record<string, never> }
  | { action: "loginPartner"; payload: Record<string, never> }
  | { action: "loadCustomers"; payload: Record<string, never> }
  | { action: "connectCustomer"; payload: { tenantId: string } }
  | { action: "loadProfiles"; payload: Record<string, never> }
  | { action: "resetSession"; payload: Record<string, never> }
  | {
      action: "registerDevice";
      payload: { profileId: string; staticGroupId?: string; hostname?: string; verbose: boolean };
    }
  | { action: "restartDevice"; payload: Record<string, never> };

export type WorkerRequest = WorkerAction & {
  requestId?: string;
};

export interface WorkerEvent {
  kind: "event" | "result";
  requestId: string;
  event?: "log" | "status" | "progress" | "customers";
  payload?: {
    message?: string;
    level?: LogLevel;
    technical?: boolean;
    step?: WorkflowStep;
    customers?: Customer[];
  };
  ok?: boolean;
  data?: unknown;
  error?: WorkerError;
}

export interface LogEntry {
  id: string;
  at: string;
  message: string;
  level: LogLevel;
  technical: boolean;
}
