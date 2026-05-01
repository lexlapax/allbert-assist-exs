defmodule AllbertAssist.Jido do
  @moduledoc """
  Jido instance for AllbertAssist. Manages agents, tasks, and supervision.

  See `config :allbert_assist, AllbertAssist.Jido, ...` in `config/config.exs`
  for runtime tuning.
  """
  use Jido, otp_app: :allbert_assist
end
