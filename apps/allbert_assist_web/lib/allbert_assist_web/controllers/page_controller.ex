defmodule AllbertAssistWeb.PageController do
  use AllbertAssistWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
