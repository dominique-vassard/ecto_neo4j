defmodule Ecto.Adapters.Neo4j.Storage do
  @behaviour Ecto.Adapter.Storage

  alias Ecto.Adapters.Neo4j.Cql.Node, as: NodeCql

  def storage_up(_) do
    :ok
  end

  def storage_down(data) do
    Application.ensure_all_started(data[:otp_app])

    conn = Bolt.Sips.conn()
    Bolt.Sips.query!(conn, NodeCql.delete_all())

    [NodeCql.list_all_constraints("", nil), NodeCql.list_all_indexes("", nil)]
    |> Enum.map(fn cql ->
      Bolt.Sips.query!(conn, cql)
      |> Map.get(:records, [])
    end)
    |> List.flatten()
    |> Enum.map(&NodeCql.drop_constraint_index_from_cql/1)
    |> Enum.map(&Bolt.Sips.query(conn, &1))

    :ok
  end
end
