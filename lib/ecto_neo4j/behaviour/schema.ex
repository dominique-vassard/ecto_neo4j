defmodule Ecto.Adapters.Neo4j.Behaviour.Schema do
  @moduledoc false

  alias Ecto.Adapters.Neo4j.Cql.Node, as: NodeCql

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

  def insert(adapter_meta, %{source: source}, fields, _on_conflict, returning, opts \\ []) do
    returning_field =
      returning
      |> Enum.map(fn
        :id -> :nodeId
        field -> field
      end)

    execute(adapter_meta, NodeCql.insert(source, format_data(fields), returning_field), opts)
  end

  def update(adapter_meta, %{source: source}, fields, filters, _returning, opts) do
    execute(adapter_meta, NodeCql.update(source, format_data(fields), format_data(filters)), opts)
  end

  def delete(adapter_meta, %{source: source}, filters, opts) do
    execute(adapter_meta, NodeCql.delete(source, format_data(filters)), opts)
  end

  defp execute(%{pid: pool}, {cql, params}, opts) do
    default_role =
      Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, bolt_role: :direct)
      |> Keyword.get(:bolt_role)

    bolt_role = Keyword.get(opts, :bolt_role, default_role)
    conn = Ecto.Adapters.Neo4j.Behaviour.Queryable.get_conn(pool, bolt_role)

    case Bolt.Sips.query(conn, cql, params) do
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
    |> Ecto.Adapters.Neo4j.Helper.manage_id(:to_db)
  end
end
