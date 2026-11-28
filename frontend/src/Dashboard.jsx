import { useEffect, useState } from "react";
import { fetchOperations, fetchOperationDetail, fetchProcedures, registerOperation } from "./api";

const STATUS_COLORS = {
  SCHEDULED: "#9aa0a6",
  PLANNED: "#1a73e8",
  READY: "#188038",
  AT_RISK: "#f9ab00",
  DELAYED: "#d93025",
  COMPLETED: "#188038",
  CANCELLED: "#9aa0a6",
};

function StatusBadge({ status }) {
  const color = STATUS_COLORS[status] || "#9aa0a6";
  return (
    <span className="badge" style={{ backgroundColor: color }}>
      {status}
    </span>
  );
}

export default function Dashboard({ session, onLogout }) {
  const { access_token: token, username, role } = session;
  const canSchedule = role === "ENT_SCHEDULER" || role === "ADMIN";

  const [procedures, setProcedures] = useState([]);
  const [operations, setOperations] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [selectedDetail, setSelectedDetail] = useState(null);

  const [procedureId, setProcedureId] = useState("");
  const [scheduledStart, setScheduledStart] = useState("");
  const [formError, setFormError] = useState(null);
  const [formMessage, setFormMessage] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  async function reloadOperations() {
    const ops = await fetchOperations(token);
    setOperations(ops);
  }

  useEffect(() => {
    fetchProcedures(token).then(setProcedures).catch((e) => setFormError(e.message));
    reloadOperations().catch((e) => setFormError(e.message));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (selectedId == null) {
      setSelectedDetail(null);
      return;
    }
    fetchOperationDetail(token, selectedId).then(setSelectedDetail).catch(() => setSelectedDetail(null));
  }, [selectedId, token]);

  async function handleSubmit(e) {
    e.preventDefault();
    setFormError(null);
    setFormMessage(null);
    setSubmitting(true);
    try {
      const isoStart = new Date(scheduledStart).toISOString();
      const result = await registerOperation(token, Number(procedureId), isoStart);
      await reloadOperations();
      setSelectedId(result.operation.operation_id);
      if (result.planning_status === "planned") {
        setFormMessage(`Operation #${result.operation.operation_id} planned with ${result.batches.length} batch(es).`);
      } else {
        setFormError(`Registered, but planning failed: ${result.message}`);
      }
    } catch (err) {
      setFormError(err.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="dashboard">
      <header className="topbar">
        <div>
          <strong>Sterilink</strong>
          <span className="role-chip">{role}</span>
        </div>
        <div>
          <span className="user-name">{username}</span>
          <button className="link-button" onClick={onLogout}>
            Log out
          </button>
        </div>
      </header>

      <div className="content">
        {canSchedule && (
          <section className="card">
            <h2>Register operation</h2>
            <form onSubmit={handleSubmit} className="inline-form">
              <label>
                Procedure
                <select value={procedureId} onChange={(e) => setProcedureId(e.target.value)} required>
                  <option value="" disabled>
                    Select a procedure
                  </option>
                  {procedures.map((p) => (
                    <option key={p.procedure_id} value={p.procedure_id}>
                      {p.procedure_name} ({p.duration_min} min)
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Scheduled start
                <input
                  type="datetime-local"
                  value={scheduledStart}
                  onChange={(e) => setScheduledStart(e.target.value)}
                  required
                />
              </label>
              <button type="submit" disabled={submitting}>
                {submitting ? "Planning..." : "Register & plan"}
              </button>
            </form>
            {formError && <div className="error">{formError}</div>}
            {formMessage && <div className="success">{formMessage}</div>}
          </section>
        )}

        <section className="card">
          <h2>Scheduled operations</h2>
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>Procedure</th>
                <th>Scheduled start</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {operations.map((op) => (
                <tr
                  key={op.operation_id}
                  className={op.operation_id === selectedId ? "selected" : ""}
                  onClick={() => setSelectedId(op.operation_id)}
                >
                  <td>{op.operation_id}</td>
                  <td>{op.procedure_name}</td>
                  <td>{new Date(op.scheduled_start).toLocaleString()}</td>
                  <td>
                    <StatusBadge status={op.status} />
                  </td>
                </tr>
              ))}
              {operations.length === 0 && (
                <tr>
                  <td colSpan={4} className="empty">
                    No operations yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>

        {selectedDetail && (
          <section className="card">
            <h2>
              Batches for operation #{selectedDetail.operation.operation_id} —{" "}
              {selectedDetail.operation.procedure_name}
            </h2>
            <table>
              <thead>
                <tr>
                  <th>Batch</th>
                  <th>Autoclave</th>
                  <th>Start</th>
                  <th>Expected end</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {selectedDetail.batches.map((b) => (
                  <tr key={b.batch_id}>
                    <td>{b.batch_id}</td>
                    <td>{b.autoclave_name}</td>
                    <td>{new Date(b.start_time).toLocaleString()}</td>
                    <td>{new Date(b.expected_end).toLocaleString()}</td>
                    <td>
                      <StatusBadge status={b.status} />
                    </td>
                  </tr>
                ))}
                {selectedDetail.batches.length === 0 && (
                  <tr>
                    <td colSpan={5} className="empty">
                      No batches planned{selectedDetail.message ? ` — ${selectedDetail.message}` : ""}.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </section>
        )}
      </div>
    </div>
  );
}
