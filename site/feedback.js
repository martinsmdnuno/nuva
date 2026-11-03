// Sends the feedback form without leaving the page. Without JavaScript the form still posts.
(() => {
  const form = document.getElementById("feedback-form");
  if (!form) return;
  const status = form.querySelector(".status");
  const button = form.querySelector("button[type=submit]");
  const pt = document.documentElement.lang.startsWith("pt");
  const text = pt
    ? { sending: "A enviar…", sent: "Obrigado. A mensagem foi enviada.", failed: "Não foi possível enviar. Tenta de novo ou abre um issue no GitHub." }
    : { sending: "Sending…", sent: "Thank you. Your message was sent.", failed: "Couldn't send it. Try again, or open an issue on GitHub." };

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    status.classList.remove("error");
    status.textContent = text.sending;
    button.disabled = true;
    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: { Accept: "application/json" },
        body: new FormData(form),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok || result.success === false) throw new Error(result.message);
      form.reset();
      status.textContent = text.sent;
    } catch {
      status.classList.add("error");
      status.textContent = text.failed;
    } finally {
      button.disabled = false;
    }
  });
})();
