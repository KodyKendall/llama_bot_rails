# LlamaBot Rails – Security & Authentication Guide

> **Audience:** Rails developers adopting the `llama_bot_rails` gem.
>
> **Scope:** How the gem prevents unauthorised code‑execution and data leakage while still allowing an AI agent to operate inside your app.

---

## 1  Threat model & design goals

| Goal                                                                                                        | Why it matters                                                             |
| ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **Integrity** – only requests originating from *your* Rails process should reach privileged agent endpoints | Prevents outsiders from forging calls that mutate your DB or execute code. |
| **Least privilege** – an agent may only hit the routes you explicitly allow                                 | Limits blast‑radius if the agent is compromised or mis‑behaves.            |
| **Operator safety‑valves** – high‑risk tools (e.g. Rails console) are **off** by default                    | Protects production environments against accidental exposure.              |

The gem uses *signed bearer tokens* for **authentication** and a **controller‑level allow‑list** for **authorization**.

---

## 2  Authenticating inbound agent requests

Every network hop that enters your Rails app passes through **`agent_controller.rb#authenticate_agent!`**. The filter is automatically prepended to all routes declared with `llama_bot_allow`.

### 2.1  How `authenticate_agent!` works  ▶ diagram

1. **Bearer token expected**
   The incoming HTTP request **must** include

   ```text
   Authorization: Bearer <signed‑token>
   ```
2. **Signature verification**
   The token is passed to `Rails.application.message_verifier(:llamabot_ws)` which checks the HMAC‐SHA256 signature against your `secret_key_base`.

3. **Failure → 401**
   Missing header, invalid signature, or expired token triggers `render status: :unauthorized`.

### 2.2  Where does the token come from?

When your Rails app initiates a call to the LlamaBot backend via a Controller action or Chat Channel, it *first* generates a fresh signed token:

```ruby
  @api_token = Rails.application.message_verifier(:llamabot_ws).generate(
      { session_id: SecureRandom.uuid },
      expires_in: 30.minutes
    )
```

It then injects this token into the agent_state payload that gets sent to LlamaBot backend.

The backend must replay this header on **every** callback to Rails, forming a cryptographic loop of trust.

---

## 3  Authorising what the agent may do

### 3.1  Per‑controller allow‑list

Add the macro at the top of any controller that the agent *should* touch:

```ruby
class PagesController < ApplicationController
  include LlamaBotRails::ControllerExtensions

  llama_bot_allow :update, :preview
end
```

Under the hood this pushes `"pages#update"` and `"pages#preview"` into the global `LlamaBotRails.allowed_routes` set. Any attempt by the agent to hit a non‑listed action is rejected with `403 Forbidden`.

### 3.2  Granular policy objects

For complex rules you can still use Pundit/CanCan etc.; the gem just ensures the request is *authentic* before your usual auth layer runs.

---

## 4  High‑risk tooling – opt‑in to production only

```ruby
# config/initializers/llama_bot_rails.rb
Rails.application.configure do
  config.llama_bot_rails.enable_console_tool = !Rails.env.production? # Default to false in production for safety.
end
```

Setting this flag to `true` exposes a virtual *Rails Console* tool to the agent (think `rails c` with full DB access). Keep it disabled unless you are in a **throw‑away dev environment**.

---

## 5  Rotation & secrets management

* **Rotate keys** by changing `secret_key_base` and setting `previous_secrets` (Rails 7.2+) so old tokens remain valid for a grace period.
* Store secrets in ENV or your credentials manager (Rails encrypted credentials, Chamber, Doppler, etc.).

---

## 6  Checklist for production hardening

1. ✅ Force **HTTPS** everywhere (TLS).
2. ✅ Confirm `Rails.env.production?` → `config.force_ssl = true`.
3. ✅ Keep `enable_console_tool` **false**.
4. ✅ Short token TTL (`exp < 2 min`).
5. ✅ Use `llama_bot_allow` sparingly.
6. ✅ Add CI tests to assert `LlamaBotRails.allowed_routes` exactly matches your intended surface‑area.

---

## 7  Troubleshooting

| Error               | Typical cause                 | Fix                                                                   |
| ------------------- | ----------------------------- | --------------------------------------------------------------------- |
| `401 Unauthorized`  | Missing/invalid/expired token | Check Rails → backend clock skew; ensure headers are proxied.         |
| `403 Forbidden`     | Route not in allow‑list       | Add `llama_bot_allow` to the controller or call a different endpoint. |
| Agent stuck in loop | Token TTL too low             | Increase `exp` to 120 s and retry.                                    |

---

### Further reading

* **ActiveSupport::MessageVerifier** – Rails API docs
* **Securing Rails Applications** – guides.rubyonrails.org/security.html

---

*Last updated: {{ date "%Y‑%m‑%d" }}*
