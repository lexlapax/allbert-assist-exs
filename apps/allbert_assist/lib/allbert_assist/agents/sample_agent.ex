defmodule AllbertAssist.Agents.SampleAgent do
  @moduledoc """
  Sample Jido.AI agent. Uses the `:fast` model alias (Anthropic Haiku
  by default — see `config/config.exs`) and exposes `Multiply` as a tool.

  ## Usage

      {:ok, pid} = Jido.AgentServer.start(agent: AllbertAssist.Agents.SampleAgent)
      {:ok, result} = AllbertAssist.Agents.SampleAgent.ask_sync(pid, "What is 23 * 19?")
  """
  use Jido.AI.Agent,
    name: "sample_agent",
    description: "Demo agent that can do arithmetic via tools.",
    model: :fast,
    tools: [AllbertAssist.Actions.Multiply],
    system_prompt: """
    You are a friendly assistant. When the user asks for arithmetic,
    use the available tools rather than computing in your head.
    """
end
