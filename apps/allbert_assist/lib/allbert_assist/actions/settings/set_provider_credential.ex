defmodule AllbertAssist.Actions.Settings.SetProviderCredential do
  @moduledoc false

  use Jido.Action,
    name: "set_provider_credential",
    description: "Guide explicit provider credential configuration.",
    category: "settings",
    tags: ["settings", "providers", "secrets"],
    schema: [
      provider: [type: :string, required: true],
      mode: [type: :atom, required: false]
    ],
    output_schema: [
      message: [type: :string, required: true],
      status: [type: :atom, required: true],
      actions: [type: {:list, :map}, required: true]
    ]

  alias AllbertAssist.Security.PermissionGate

  @impl true
  def run(%{provider: provider} = params, context) do
    mode = Map.get(params, :mode, :configure)

    case mode do
      :raw_prompt_secret ->
        deny_raw_prompt(provider, context)

      :raw_secret_read ->
        deny_secret_read(provider, context)

      _mode ->
        credential_guidance(provider, context)
    end
  end

  defp credential_guidance(provider, context) do
    permission_decision = PermissionGate.authorize(:settings_secret_write, context)

    {:ok,
     %{
       message:
         "Credential entry for #{provider} must use the explicit CLI or LiveView secret form. Use `mix allbert.settings providers set-key #{provider}` or the Settings page provider key form.",
       status: PermissionGate.response_status(permission_decision),
       actions: [
         action(
           provider,
           :completed,
           :settings_secret_write,
           permission_decision,
           :credential_flow_guidance
         )
       ]
     }}
  end

  defp deny_raw_prompt(provider, context) do
    permission_decision = PermissionGate.authorize(:settings_secret_write, context)

    {:ok,
     %{
       message:
         "I will not store provider credentials from natural-language prompt text. Use the explicit CLI stdin prompt or the Settings page secret form so the value stays out of traces.",
       status: :denied,
       actions: [
         action(
           provider,
           :denied,
           :settings_secret_write,
           permission_decision,
           :raw_prompt_secret_refused
         )
       ]
     }}
  end

  defp deny_secret_read(provider, context) do
    permission_decision = PermissionGate.authorize(:settings_secret_read, context)

    {:ok,
     %{
       message:
         "I cannot display raw provider secrets. I can show only redacted credential status.",
       status: PermissionGate.response_status(permission_decision),
       actions: [
         action(
           provider,
           :denied,
           :settings_secret_read,
           permission_decision,
           :raw_secret_read_denied
         )
       ]
     }}
  end

  defp action(provider, status, permission, permission_decision, reason) do
    %{
      name: "set_provider_credential",
      status: status,
      permission: permission,
      permission_decision: permission_decision,
      settings_metadata: %{
        provider: provider,
        secret_status: :redacted,
        reason: reason
      }
    }
  end
end
