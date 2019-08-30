defmodule EctoNeo4j.Behaviour.Schema do
  @moduledoc false

  alias EctoNeo4j.Cql.Node, as: NodeCql

  def autogenerate(:id), do: :erlang.system_time(:microsecond)
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  def insert_all(
        adapter,
        schema_meta,
        _header,
        entries,
        on_conflict,
        returning,
        options
      ) do
    inserts =
      entries
      |> Enum.map(fn data ->
        insert(adapter, schema_meta, data, on_conflict, returning, options)
      end)

    case returning do
      [] -> {length(inserts), nil}
      _ -> {length(inserts), Enum.map(inserts, fn {_, v} -> v end)}
    end
  end

  def insert(_adapter, %{source: source}, fields, _on_conflict, returning, _opts \\ []) do
    returning_field =
      returning
      |> Enum.map(fn
        :id -> :nodeId
        field -> field
      end)

    NodeCql.insert(source, format_data(fields), returning_field)
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

      {:ok, %Bolt.Sips.Response{records: [record]}} ->
        {:ok, record}

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
