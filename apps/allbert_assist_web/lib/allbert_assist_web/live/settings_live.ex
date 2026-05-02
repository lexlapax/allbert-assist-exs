defmodule AllbertAssistWeb.SettingsLive do
  @moduledoc """
  Operator Settings Central surface.
  """

  use AllbertAssistWeb, :live_view

  alias AllbertAssist.Settings

  @default_key "operator.communication_style"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, refresh(socket, @default_key)}
  end

  @impl true
  def handle_event("select_setting", %{"key" => key}, socket) do
    {:noreply, refresh(socket, key)}
  end

  def handle_event("save_setting", %{"setting" => %{"key" => key, "value" => value}}, socket) do
    socket =
      case Settings.put(key, value, %{actor: "local", channel: :live_view}) do
        {:ok, setting} ->
          socket
          |> put_flash(:info, "Setting saved.")
          |> assign(:diagnostics, "")
          |> assign(:last_audit_path, audit_path(setting.diagnostics))
          |> refresh(key)

        {:error, reason} ->
          socket
          |> assign(:diagnostics, inspect(reason))
          |> refresh_forms(key, value)
      end

    {:noreply, socket}
  end

  def handle_event(
        "save_provider_key",
        %{"provider" => %{"provider" => provider, "api_key" => api_key}},
        socket
      ) do
    secret_ref = "secret://providers/#{provider}/api_key"

    socket =
      case Settings.Secrets.put_secret(secret_ref, api_key, %{actor: "local", channel: :live_view}) do
        {:ok, result} ->
          socket
          |> put_flash(:info, "Provider credential saved.")
          |> assign(:diagnostics, "")
          |> assign(:last_audit_path, audit_path(Map.get(result, :diagnostics, [])))
          |> refresh(socket.assigns.selected_key)

        {:error, reason} ->
          socket
          |> assign(:diagnostics, inspect(reason))
          |> refresh_forms(socket.assigns.selected_key, socket.assigns.selected_value)
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl px-6 py-8">
        <header class="mb-6">
          <h1 class="text-2xl font-semibold">Settings Central</h1>
        </header>

        <div class="grid gap-6 lg:grid-cols-[minmax(220px,320px)_1fr]">
          <section id="settings-list" class="space-y-2">
            <button
              :for={setting <- @settings}
              type="button"
              phx-click="select_setting"
              phx-value-key={setting.key}
              class={[
                "block w-full rounded border px-3 py-2 text-left text-sm transition",
                setting.key == @selected_key && "border-blue-500 bg-blue-50",
                setting.key != @selected_key && "border-base-300 hover:border-base-content/40"
              ]}
            >
              <span class="block font-medium">{setting.key}</span>
              <span class="text-xs text-base-content/60">{setting.source}</span>
            </button>
          </section>

          <main class="space-y-6">
            <section>
              <.form
                for={@setting_form}
                id="settings-form"
                phx-submit="save_setting"
                class="space-y-3"
              >
                <.input field={@setting_form[:key]} id="settings-key" type="text" label="Key" />
                <.input field={@setting_form[:value]} id="settings-value" type="text" label="Value" />
                <button id="settings-save" type="submit" class="btn btn-primary">Save</button>
              </.form>

              <pre
                id="settings-explanation"
                class="mt-4 whitespace-pre-wrap rounded border border-base-300 p-3 text-sm"
              >{@explanation}</pre>
              <p id="settings-diagnostics" class="mt-3 text-sm text-error">{@diagnostics}</p>
              <p :if={@last_audit_path} id="settings-audit" class="mt-2 text-xs text-base-content/60">
                Audit: {@last_audit_path}
              </p>
            </section>

            <section id="provider-profiles" class="space-y-2">
              <h2 class="text-lg font-medium">Providers</h2>
              <div :for={provider <- @providers} class="rounded border border-base-300 p-3 text-sm">
                <div class="font-medium">{provider.name}</div>
                <div>Type: {provider.type}</div>
                <div>Enabled: {inspect(provider.enabled)}</div>
                <div>Credential: {provider.credential_status}</div>
              </div>
            </section>

            <section id="model-profiles" class="space-y-2">
              <h2 class="text-lg font-medium">Models</h2>
              <div :for={model <- @models} class="rounded border border-base-300 p-3 text-sm">
                <div class="font-medium">{model.name}</div>
                <div>Provider: {model.provider}</div>
                <div>Model: {model.model}</div>
                <div>Credential: {model.credential_status}</div>
              </div>
            </section>

            <section>
              <.form
                for={@provider_form}
                id="provider-key-form"
                phx-submit="save_provider_key"
                class="space-y-3"
              >
                <.input field={@provider_form[:provider]} type="text" label="Provider" />
                <.input field={@provider_form[:api_key]} type="password" label="API key" />
                <button type="submit" class="btn btn-secondary">Set Provider Key</button>
              </.form>
            </section>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp refresh(socket, selected_key) do
    {:ok, settings} = Settings.list()
    {:ok, providers} = Settings.list_provider_profiles()
    {:ok, models} = Settings.list_model_profiles()

    setting = Enum.find(settings, &(&1.key == selected_key)) || List.first(settings)

    socket
    |> assign(:settings, settings)
    |> assign(:providers, providers)
    |> assign(:models, models)
    |> assign(:selected_key, setting.key)
    |> assign(:selected_value, setting.value)
    |> assign(:explanation, explanation(setting))
    |> assign_new(:diagnostics, fn -> "" end)
    |> assign_new(:last_audit_path, fn -> nil end)
    |> refresh_forms(setting.key, setting.value)
  end

  defp refresh_forms(socket, key, value) do
    socket
    |> assign(:setting_form, to_form(%{"key" => key, "value" => form_value(value)}, as: :setting))
    |> assign(:provider_form, to_form(%{"provider" => "openai", "api_key" => ""}, as: :provider))
  end

  defp explanation(setting) do
    layers =
      setting.layers
      |> Enum.map(&"- #{&1.source}: #{inspect(&1.value)}")
      |> Enum.join("\n")

    """
    #{setting.key}
    Value: #{inspect(setting.value)}
    Source: #{setting.source}
    Writable: #{setting.writable?}

    Layers:
    #{layers}
    """
    |> String.trim()
  end

  defp form_value(value) when is_binary(value), do: value
  defp form_value(value), do: inspect(value)

  defp audit_path(diagnostics), do: Enum.find_value(diagnostics, &Map.get(&1, :audit_path))
end
