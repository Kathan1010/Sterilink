import { useState } from "react";
import { login } from "./api";

export default function Login({ onLoggedIn }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const data = await login(username, password);
      onLoggedIn(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="centered">
      <form className="card" onSubmit={handleSubmit}>
        <h1>Sterilink</h1>
        <p className="subtitle">Sterilisation Workflow Management</p>

        <label>
          Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} autoFocus />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>

        {error && <div className="error">{error}</div>}

        <button type="submit" disabled={loading}>
          {loading ? "Signing in..." : "Sign in"}
        </button>

        <p className="hint">
          Demo users: scheduler1/sched123, staff1/staff123, admin1/admin123
        </p>
      </form>
    </div>
  );
}
