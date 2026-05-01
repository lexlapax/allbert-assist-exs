defmodule AllbertAssist.MemoryTest do
  use ExUnit.Case, async: false

  alias AllbertAssist.Memory

  setup do
    original_config = Application.get_env(:allbert_assist, Memory)

    root =
      Path.join(System.tmp_dir!(), "allbert-memory-test-#{System.unique_integer([:positive])}")

    Application.put_env(:allbert_assist, Memory, root: root)

    on_exit(fn ->
      if original_config do
        Application.put_env(:allbert_assist, Memory, original_config)
      else
        Application.delete_env(:allbert_assist, Memory)
      end

      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  test "creates the memory root and initial categories", %{root: root} do
    assert Memory.ensure_root!() == root

    for category <- Memory.categories() do
      assert File.dir?(Path.join(root, Atom.to_string(category)))
    end
  end

  test "appends human-readable markdown memory", %{root: root} do
    assert {:ok, entry} =
             Memory.append(%{
               category: :notes,
               body: "My planning docs should be implementation-ready.",
               source_signal_id: "sig-123",
               actor: "local",
               agent: "AllbertAssist.Agents.IntentAgent",
               channel: :test
             })

    assert entry.path =~ Path.join(root, "notes")
    assert File.exists?(entry.path)

    markdown = File.read!(entry.path)
    assert markdown =~ "# Memory: My planning docs should be implementation-ready."
    assert markdown =~ "- Source signal: sig-123"
    assert markdown =~ "- Actor: local"
    assert markdown =~ "- Agent: AllbertAssist.Agents.IntentAgent"
    assert markdown =~ "## Body"
    assert markdown =~ "My planning docs should be implementation-ready."
  end

  test "reads recent markdown memory ranked by query" do
    assert {:ok, _entry} =
             Memory.append(%{
               category: :notes,
               body: "My planning docs should be implementation-ready.",
               source_signal_id: "sig-123",
               actor: "local",
               agent: "AllbertAssist.Agents.IntentAgent",
               channel: :test
             })

    assert {:ok, entries} = Memory.recent(query: "What do you remember about my planning docs?")

    assert [%{body: body, summary: summary} | _rest] = entries
    assert body =~ "planning docs"
    assert summary =~ "planning docs"
  end

  test "recent memory excludes trace entries unless requested" do
    assert {:ok, _trace} =
             Memory.append(%{
               category: :traces,
               body: "Trace for a concise milestone handoff memory write.",
               source_signal_id: "sig-trace",
               actor: "local",
               agent: "AllbertAssist.Runtime",
               channel: :test
             })

    assert {:ok, _preference} =
             Memory.append(%{
               category: :preferences,
               body: "I like concise milestone handoffs.",
               source_signal_id: "sig-pref",
               actor: "local",
               agent: "AllbertAssist.Agents.IntentAgent",
               channel: :test
             })

    assert {:ok, entries} = Memory.recent(query: "milestone handoffs")

    assert Enum.all?(entries, &(&1.category != :traces))
    assert [%{category: :preferences}] = entries

    assert {:ok, trace_entries} =
             Memory.recent(query: "milestone handoffs", categories: [:traces])

    assert [%{category: :traces}] = trace_entries
  end
end
