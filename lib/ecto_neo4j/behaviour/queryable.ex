defmodule EctoNeo4j.Behaviour.Queryable do
  alias EctoNeo4j.QueryBuilder

  def checkout(_adapter_meta, _opts, _callback) do
    raise "checkout/1 is not supported"
  end

  def prepare(:all, query) do
    {:nocache, {:match, query}}
  end

  def prepare(:delete_all, query) do
    {:nocache, {:delete, query}}
  end

  def prepare(:update_all, query) do
    {:nocache, {:update, query}}
  end

  def execute(
        %{pid: pool},
        %{sources: {{_, _schema, _}}},
        {:nocache, {query_type, query}},
        sources,
        _preprocess,
        opts \\ []
      ) do
    {cypher_query, params} = QueryBuilder.build(query_type, query, sources, opts)

    conn = EctoNeo4j.Behaviour.Queryable.get_conn(pool)

    case Bolt.Sips.query(conn, cypher_query, params) do
      {:ok, results} ->
        res = Enum.map(results.results, &format_results(&1, query.select))

        {length(res), format_final_result(query_type, res)}

      {:error, error} ->
        raise error
    end
  end

  defp format_final_result(query_type, results) when query_type in [:update, :delete] do
    case Enum.filter(results, fn v -> length(v) > 0 end) do
      [] -> nil
      result -> result
    end
  end

  defp format_final_result(_, results) do
    results
  end

  defp format_results(raw_results, %Ecto.Query.SelectExpr{fields: fields}) do
    results = manage_id(raw_results)

    fields
    # |> Enum.map(fn {{:., _, [{:&, [], [0]}, field_atom]}, _, _} -> field_atom end)
    |> Enum.map(&format_result_field/1)
    |> Enum.into([], fn key ->
      {key, Map.fetch!(results, key)}
    end)
    |> Keyword.values()
  end

  defp format_results(_, nil) do
    []
  end

  defp format_result_field(%Ecto.Query.Tagged{value: field}) do
    resolve_field_name(field)
  end

  defp format_result_field({{:., _, [{:&, [], [0]}, _]}, _, _} = field) do
    resolve_field_name(field)
  end

  defp format_result_field({aggregate, [], [field | distinct]}) do
    cql_distinct =
      if length(distinct) > 0 do
        "DISTINCT "
      else
        ""
      end

    Atom.to_string(aggregate) <> "(#{cql_distinct}n." <> resolve_field_name(field) <> ")"
  end

  defp resolve_field_name({{:., _, [{:&, [], [0]}, field_name]}, [], []}) do
    Atom.to_string(field_name)
  end

  defp manage_id(%{"nodeId" => node_id} = data) do
    data
    |> Map.put("id", node_id)
    |> Enum.reject(fn {key, _} -> key == "nodeId" end)
    |> Map.new()
  end

  defp manage_id(data) do
    data
  end

  @doc """
  Launch the given query with params on database.

  Returns all found results, on raise a `Bolt.Sips.Exception` in case of error.

  As database errors should not be silently ignored, a wrong query will crash.

  ### Example
      EctoNeo4j.Repo.query("MATCH (n:Post {uuid: {uuid}}", %{uuid: "unique_id"})
  """
  def query(cql, params \\ %{}, _opts \\ []) do
    Bolt.Sips.query(Bolt.Sips.conn(), cql, params)
  end

  @doc """
  Same as `query` but raises in case of error;
  """
  def query!(cql, params \\ %{}, _opts \\ []) do
    Bolt.Sips.query!(Bolt.Sips.conn(), cql, params)
  end

  @doc """
  Not implemented yet.
  """
  def stream(_, _, _, _, _, _opts \\ []) do
    raise(
      ArgumentError,
      "stream/6 is not supported by adapter, use EctoMnesia.Table.Stream.new/2 instead"
    )
  end

  def in_transaction?(%{pid: pool}) do
    match?(%DBConnection{conn_mode: :transaction}, get_conn(pool))
  end

  # def transaction(repo, fun_or_multi, opts \\ [])

  def transaction(_, %Ecto.Multi{}, _) do
    raise "not supported"
  end

  def transaction(repo, opts, fun) do
    checkout_or_transaction(:transaction, repo, opts, fun)
  end

  def rollback(%{pid: pool}, value) do
    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        Bolt.Sips.rollback(conn, value)

      _ ->
        raise "cannot call rollback outside of transaction"
    end
  end

  ## Connection helpers

  defp checkout_or_transaction(fun, %{pid: pool}, opts, callback) do
    callback = fn conn ->
      previous_conn = put_conn(pool, conn)

      try do
        callback.()
      after
        reset_conn(pool, previous_conn)
      end
    end

    conn_role = Keyword.get(opts, :bolt_role, :direct)

    apply(Bolt.Sips, fun, [get_conn_or_pool(pool, conn_role), callback, opts])
  end

  defp get_conn_or_pool(pool, role) do
    Process.get(key(pool), Bolt.Sips.conn(role))
  end

  def get_conn(pool) do
    Process.get(key(pool)) || Bolt.Sips.conn()
  end

  defp put_conn(pool, conn) do
    Process.put(key(pool), conn)
  end

  defp reset_conn(pool, conn) do
    if conn do
      put_conn(pool, conn)
    else
      Process.delete(key(pool))
    end
  end

  defp key(pool), do: {__MODULE__, pool}
end
