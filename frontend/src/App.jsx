import { useState } from "react";
import Login from "./Login";
import Dashboard from "./Dashboard";

export default function App() {
  const [session, setSession] = useState(null);

  if (!session) {
    return <Login onLoggedIn={setSession} />;
  }

  return <Dashboard session={session} onLogout={() => setSession(null)} />;
}
