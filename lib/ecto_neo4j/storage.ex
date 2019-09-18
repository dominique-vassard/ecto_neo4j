defmodule EctoNeo4j.Storage do
  @behaviour Ecto.Adapter.Storage

  def storage_up(_) do
    :ok
  end

  def storage_down(data) do
    Application.ensure_all_started(data[:otp_app])

    Bolt.Sips.query!(Bolt.Sips.conn(), EctoNeo4j.Cql.Node.delete_all())

    :ok
  end
end
