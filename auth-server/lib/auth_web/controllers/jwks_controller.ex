defmodule AuthWeb.JwksController do
  use AuthWeb, :controller

  def index(conn, _params) do
    json(conn, Auth.Token.Keys.jwks())
  end
end
