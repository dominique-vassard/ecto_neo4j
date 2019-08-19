defmodule EctoNeo4j.Behaviour.Schema do
  alias EctoNeo4j.Cql.Node, as: NodeCql

  def autogenerate(:id), do: :erlang.system_time(:seconds)
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  def insert_all(adapter_meta, schema_meta, header, entries, on_conflict, returning, options) do
    {0, []}
  end

  def insert(_adapter, %{source: source}, fields, _on_conflict, _returning, _opts \\ []) do
    NodeCql.insert(source, format_data(fields))
    |> execute()
  end

  def update(_adapter_meta, %{source: source}, fields, filters, _returning, _options) do
    NodeCql.update(source, format_data(fields), format_data(filters))
    |> execute()
  end

  def delete(adapter_meta, schema_meta, filters, _options) do
    # {:ok, []}
    {:error, :not_impmlemented}
  end

  defp execute({cql, params}) do
    case EctoNeo4j.Behaviour.Queryable.query(cql, params) do
      {:ok, %Bolt.Sips.Response{results: [%{"n" => _record}]}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_data(data) do
    data
    |> Map.new()
    |> manage_id()
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

  defp manage_id(data), do: data
end
