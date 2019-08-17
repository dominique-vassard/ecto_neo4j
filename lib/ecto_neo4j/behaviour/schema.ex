defmodule EctoNeo4j.Behaviour.Schema do
  alias EctoNeo4j.Cql.Node, as: NodeCql

  def autogenerate(:id), do: :erlang.system_time(:seconds)
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  def insert_all(adapter_meta, schema_meta, header, entries, on_conflict, returning, options) do
    {0, []}
  end

  def insert(_adapter, %{source: source}, fields, _on_conflict, _returning, _opts \\ []) do
    data =
      fields
      |> Map.new()
      |> manage_id()

    {cql, params} = NodeCql.insert_new(source, data)

    case EctoNeo4j.Behaviour.Queryable.query(cql, params) do
      {:ok, %Bolt.Sips.Response{results: [%{"n" => _record}]}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update(adapter_meta, schema_meta, fields, filters, [] = returning, _options) do
    {:ok, []}
  end

  def delete(adapter_meta, schema_meta, filters, _options) do
    {:ok, []}
  end

  defp manage_node_id(%{nodeId: node_id} = data) do
    data
    |> Map.put(:id, node_id)
    |> Map.drop([:node_id])
  end

  defp manage_id(%{id: id} = data) do
    data
    |> Map.put(:node_id, id)
    |> Map.drop([:id])
  end
end
