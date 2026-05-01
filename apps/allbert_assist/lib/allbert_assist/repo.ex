defmodule AllbertAssist.Repo do
  use Ecto.Repo,
    otp_app: :allbert_assist,
    adapter: Ecto.Adapters.SQLite3
end
