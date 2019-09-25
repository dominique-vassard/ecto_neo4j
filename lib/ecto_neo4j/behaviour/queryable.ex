defmodule Ecto.Adapters.Neo4j.Behaviour.Queryable do
  alias Ecto.Adapters.Neo4j.QueryBuilder

  @chunk_size Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, chunk_size: 10_000)
              |> Keyword.get(:chunk_size)
  @batch Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, batch: false)
         |> Keyword.get(:batch)
  @bolt_role Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, bolt_role: :direct)
             |> Keyword.get(:bolt_role)

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
        preprocess,
        opts \\ []
      ) do
    is_batch? = Keyword.get(preprocess, :batch, @batch)
    bolt_role = Keyword.get(preprocess, :bolt_role, @bolt_role)

    opts =
      opts ++ [batch: is_batch?, chunk_size: Keyword.get(preprocess, :chunk_size, @chunk_size)]

    {cypher_query, params} = QueryBuilder.build(query_type, query, sources, opts)

    conn = get_conn(pool, bolt_role)

    run_query(conn, query, cypher_query, params, is_batch?, query_type, opts)
  end

  defp run_query(_, _, query, params, true, query_type, opts)
       when query_type in [:update, :delete] do
    batch_type =
      if query_type == :update do
        :with_skip
      else
        :basic
      end

    case batch_query(query, params, batch_type, opts) do
      {:ok, []} ->
        nil

      {:error, error} ->
        raise Bolt.Sips.Exception, error.message
    end
  end

  defp run_query(conn, query, cypher_query, params, _is_batch?, query_type, _opts) do
    case Bolt.Sips.query(conn, cypher_query, params) do
      {:ok, results} ->
        res = Enum.map(results.results, &format_results(&1, query.select))

        {length(res), format_final_result(query_type, res)}

      {:error, error} ->
        raise Bolt.Sips.Exception, error.message
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
      Ecto.Adapters.Neo4j.Repo.query("MATCH (n:Post {uuid: {uuid}}", %{uuid: "unique_id"})
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

  def batch_query!(cql, params \\ %{}, batch_type \\ :basic, opts \\ []) do
    case batch_query(cql, params, batch_type, opts) do
      {:ok, []} -> {:ok, []}
      {:error, error} -> raise Bolt.Sips.Exception, error.message
    end
  end

  def batch_query(cql, params \\ %{}, batch_type \\ :basic, opts \\ [])

  def batch_query(cql, cql_params, :basic, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @chunk_size)

    params = Map.merge(cql_params, %{limit: chunk_size})

    do_batch_query(cql, params, 1)
  end

  def batch_query(cql, cql_params, :with_skip, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @chunk_size)
    params = Map.merge(cql_params, %{limit: chunk_size})

    do_batch_query_with_skip(cql, params, 0, 1)
  end

  defp do_batch_query(_, _, 0) do
    {:ok, []}
  end

  defp do_batch_query(cql, params, _) do
    case query(cql, params) do
      {:ok, %Bolt.Sips.Response{results: [%{"nb_touched_nodes" => nb_nodes}]}} ->
        do_batch_query(cql, params, nb_nodes)

      {:error, _} = error ->
        error
    end
  end

  defp do_batch_query_with_skip(_, _, _, 0) do
    {:ok, []}
  end

  defp do_batch_query_with_skip(cql, params, skip, _) do
    params = Map.put(params, :skip, skip)
    %Bolt.Sips.Response{results: [%{"nb_touched_nodes" => nb_nodes}]} = query!(cql, params)
    do_batch_query_with_skip(cql, params, skip + params.limit, nb_nodes)
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

    conn_role = Keyword.get(opts, :bolt_role, @bolt_role)

    apply(Bolt.Sips, fun, [get_conn_or_pool(pool, conn_role), callback, opts])
  end

  defp get_conn_or_pool(pool, bolt_role) do
    Process.get(key(pool), Bolt.Sips.conn(bolt_role))
  end

  def get_conn(pool, bolt_role \\ nil) do
    bolt_role = bolt_role || @bolt_role
    Process.get(key(pool)) || Bolt.Sips.conn(bolt_role)
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
