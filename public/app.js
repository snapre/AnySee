const form = document.querySelector("[data-waitlist-form]");
const statusEl = document.querySelector("[data-form-status]");

function setStatus(message, state) {
  if (!statusEl) return;
  statusEl.className = `form-status ${state || ""}`.trim();
  statusEl.replaceChildren(document.createTextNode(message));
}

function setFallbackStatus(formData, message, contactEmail = "hello@anysee.bar") {
  if (!statusEl) return;

  const email = String(formData.get("email") || "").trim();
  const name = String(formData.get("name") || "").trim();
  const note = String(formData.get("note") || "").trim();
  const body = [
    name ? `Name: ${name}` : "",
    email ? `Email: ${email}` : "",
    note ? `Use case: ${note}` : "",
  ].filter(Boolean).join("\n");
  const safeContactEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail) ? contactEmail : "hello@anysee.bar";
  const href = `mailto:${safeContactEmail}?subject=${encodeURIComponent("AnySee waitlist")}&body=${encodeURIComponent(body)}`;
  const prefix = document.createTextNode(`${message} `);
  const link = document.createElement("a");
  link.href = href;
  link.textContent = `Email ${safeContactEmail} instead.`;
  statusEl.className = "form-status error";
  statusEl.replaceChildren(prefix, link);
}

function isLikelyEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

if (form) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const submitButton = form.querySelector("button[type='submit']");
    const formData = new FormData(form);
    const email = String(formData.get("email") || "").trim();

    if (!isLikelyEmail(email)) {
      setStatus("Enter a valid email address.", "error");
      return;
    }

    submitButton.disabled = true;
    submitButton.textContent = "Joining...";
    setStatus("Sending...", "");

    try {
      const response = await fetch(form.action, {
        method: "POST",
        body: formData,
        headers: { Accept: "application/json" },
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok || payload.ok !== true) {
        const submitError = new Error(payload.error || "The waitlist endpoint is not ready yet.");
        submitError.contactEmail = payload.contactEmail;
        throw submitError;
      }

      form.reset();
      setStatus("You are on the list. I will send the first build notes when they are ready.", "success");
    } catch (error) {
      setFallbackStatus(formData, error.message || "The waitlist endpoint is not ready yet.", error.contactEmail);
    } finally {
      submitButton.disabled = false;
      submitButton.textContent = "Join waitlist";
    }
  });
}
