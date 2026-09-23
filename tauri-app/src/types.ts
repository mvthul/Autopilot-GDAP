export type WorkflowStep = "login" | "customer" | "configure" | "register" | "complete";

export type LogLevel = "info" | "success" | "warning" | "error";

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
}

export interface PreflightResult {
  isAdministrator: boolean;
  powershellVersion: string;
  graphModuleInstalled: boolean;
}

export interface RegisterResult {
  serialNumber: string;
  staticGroupName?: string;
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
  event?: "log" | "status" | "progress";
  payload?: {
    message?: string;
    level?: LogLevel;
    technical?: boolean;
    step?: WorkflowStep;
  };
  ok?: boolean;
  data?: unknown;
  error?: string;
}

export interface LogEntry {
  id: string;
  at: string;
  message: string;
  level: LogLevel;
  technical: boolean;
}
