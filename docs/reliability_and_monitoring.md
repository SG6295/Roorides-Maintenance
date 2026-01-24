# System Reliability & Monitoring Plan

## Critical Triggers & Alarms
To ensure high availability and rapid response, we recommend setting up the following monitors.

### 1. Database & Backend (Supabase)
*   **Database CPU/RAM Utilization**:
    *   *Trigger*: Warning > 80%, Critical > 90%.
    *   *Risk*: High traffic filters or complex analytics (e.g., `get_maintenance_stats`) could spike CPU, causing slow loads or timeouts.
*   **Edge Function Failures**:
    *   *Monitor*: 5xx Error Rate on `daily-digest` and `send-email`.
    *   *Risk*: If `daily-digest` fails, Admins won't know about overdue SLAs.
    *   *Action*: Supabase Dashboard -> Logs -> Set notification on recurring errors.

### 2. External Services (Integrations)
*   **Resend (Email Delivery)**:
    *   *Trigger*: Bounce Rate > 5% or Failed Delivery Events.
    *   *Risk*: Critical Password Reset emails or SLA Alerts not reaching users.
    *   *Mitigation*: Monitor Resend Dashboard. Check `audit_logs` for email dispatch failures (if we add logging there).
*   **Google Drive API (Photos)**:
    *   *Trigger*: API Quota Exceeded or Auth Errors (401/403).
    *   *Risk*: Supervisors cannot upload proof photos. Ticket creation blocking.
    *   *Fallback*: Ensure UI handles upload failure gracefully (allow text-only ticket creation).

### 3. Frontend / User Experience
*   **Client-Side Errors (Sentry/LogRocket)**:
    *   *Trigger*: New Unhandled Exception in core flows (Login, Create Ticket).
    *   *Risk*: White screen of death (WSOD) prevents work.
*   **Uptime Monitoring (Pingdom)**:
    *   *Trigger*: Site unreachable (Non-200 status).
    *   *Action*: PagerDuty/Slack alert to Dev team.

---

## Known Risks & Mitigations

| Risk Area | Scenario | Impact | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Data Integrity** | Supervisor rates a ticket but connection drops. | Rating lost, ticket remains unrated. | **Resolved**: Audit Logs track attempts. UI shows "Saving..." state. |
| **Cron Jobs** | `pg_cron` fails to trigger `daily-digest`. | No morning summary email. | **Manual Check**: Admin can trigger digest manually via Edge Function URL. |
| **Performance** | Analytics Dashboard loads too strictly for 10k+ tickets. | Page freeze / Timeout. | **Optimization**: `get_maintenance_stats` uses DB aggregation, not client-side. Add indexes if slow. |
| **Security** | Maintenance Exec leaves session open on shared PC. | Unauthorized edits. | **Session Timeout**: Supabase Auth handles expiry. Recommend forcing re-login every 24h. |
| **Storage** | Google Drive fills up. | Photo uploads fail. | **alert**: Monitor Google Drive storage usage. |

## Immediate Actions for Admin
1.  **Enable Log Alerts** in Supabase Project Settings.
2.  **Subscribe** to Resend Delivery Issues (webhook or dashboard).
3.  **Test Manual Fallbacks**: verified that `get_maintenance_stats` is performant.
