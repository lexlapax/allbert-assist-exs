defmodule AllbertAssist.RuntimeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AllbertAssist.Runtime

  setup do
    original_config = Application.get_env(:allbert_assist, Runtime)
    original_logger_level = Logger.level()
    parent = self()

    runner = fn signal, request ->
      send(parent, {:agent_runner_called, signal.type, request.text, request.channel})
      {:ok, %{message: "Runtime response: #{request.text}", status: :completed, actions: []}}
    end

    Application.put_env(:allbert_assist, Runtime, agent_runner: runner)
    Logger.configure(level: :info)

    on_exit(fn ->
      Logger.configure(level: original_logger_level)

      if original_config do
        Application.put_env(:allbert_assist, Runtime, original_config)
      else
        Application.delete_env(:allbert_assist, Runtime)
      end
    end)
  end

  test "submits user input through the configured signal-first runner" do
    response =
      capture_log([level: :info], fn ->
        assert {:ok, response} =
                 Runtime.submit_user_input(%{
                   text: "Say hello from the runtime boundary.",
                   channel: :test,
                   operator_id: "local"
                 })

        assert response.message == "Runtime response: Say hello from the runtime boundary."
        assert response.status == :completed
        assert response.trace_id == nil
        assert is_binary(response.input_signal_id)
        assert is_binary(response.signal_id)
        response
      end)

    assert response =~ "allbert.input.received"
    assert response =~ "allbert.agent.responded"

    assert_received {:agent_runner_called, "allbert.input.received",
                     "Say hello from the runtime boundary.", :test}
  end

  test "accepts string keys and default operator identity" do
    assert {:ok, response} =
             Runtime.submit_user_input(%{
               "text" => "Hello with string keys.",
               "channel" => "test"
             })

    assert response.message == "Runtime response: Hello with string keys."

    assert_received {:agent_runner_called, "allbert.input.received", "Hello with string keys.",
                     "test"}
  end

  test "rejects empty text before calling the runner" do
    assert {:error, :empty_text} =
             Runtime.submit_user_input(%{
               text: "   ",
               channel: :test,
               operator_id: "local"
             })

    refute_received {:agent_runner_called, _, _, _}
  end

  test "documents the first runtime signal names" do
    assert Runtime.signal_types() == %{
             input_received: "allbert.input.received",
             agent_responded: "allbert.agent.responded",
             action_requested: "allbert.action.requested",
             action_completed: "allbert.action.completed",
             memory_appended: "allbert.memory.appended",
             trace_recorded: "allbert.trace.recorded"
           }
  end
end
