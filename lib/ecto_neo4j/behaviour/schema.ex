defmodule EctoNeo4j.Behaviour.Schema do
  alias EctoNeo4j.Cql.Node, as: NodeCql

  def autogenerate(:id), do: :erlang.system_time(:seconds)
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  def insert_all(
        _adapter_meta,
        _schema_meta,
        _header,
        _entries,
        _on_conflict,
        _returning,
        _options
      ) do
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

  def delete(_adapter_meta, %{source: source}, filters, _options) do
    NodeCql.delete(source, format_data(filters))
    |> execute()
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
    |> EctoNeo4j.Helper.manage_id(:to_db)
  end
end
