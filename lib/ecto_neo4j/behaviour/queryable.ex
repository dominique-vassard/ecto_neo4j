defmodule EctoNeo4j.Behaviour.Queryable do
  # import Ecto.Query
  # alias EctoNeo4j.Cql.Node, as: NodeCql
  alias EctoNeo4j.QueryBuilder

  def prepare(:all, query) do
    {:nocache, query}
  end

  def execute(
        _repo,
        %{sources: {{_, _schema, _}}},
        {:nocache, query},
        sources,
        _preprocess,
        opts \\ []
      ) do
    # query
    # |> Map.from_struct()
    # |> IO.inspect()

    {cypher_query, params} = QueryBuilder.build(query, sources, opts)
    # |> IO.inspect()

    # do_execute(query)

    res =
      case query(cypher_query, params) do
        {:ok, results} ->
          Enum.map(results.results, &format_results(&1, query.select))

        {:error, error} ->
          raise error
      end

    {1, res}
  end

  # defp format_results(%{"n" => record}, _, schema) do
  #   to_struct(record, schema)
  # end

  defp format_results(results, %Ecto.Query.SelectExpr{fields: fields}) do
    fields
    |> Enum.map(fn {{:., _, [{:&, [], [0]}, field_atom]}, _, _} -> field_atom end)
    |> Enum.into([], fn key ->
      {key, Map.fetch!(results, "n.#{Atom.to_string(key)}")}
    end)
    |> Keyword.values()
  end

  # defp format_results(results, fields, _) do
  # TODO
  # results
  # |> Enum.filter(fun)
  # end

  # defp do_execute(queryable_or_model, opts \\ [])

  # defp do_execute(queryable, _opts) do
  #   %{from: %Ecto.Query.FromExpr{source: {_, model}}} = Map.from_struct(queryable)
  #   {cql, params} = build_query(queryable)

  #   case query(cql, params) do
  #     {:ok, results} ->
  #       results
  #       |> Enum.map(fn
  #         %{"n" => record} ->
  #           to_struct(record, model)

  #         results ->
  #           results
  #           |> Map.values()
  #       end)

  #     {:error, error} ->
  #       raise error
  #   end
  # end

  # defp do_execute(model, opts) do
  #   query = from(m in model)
  #   do_execute(query, opts)
  # end

  # defp build_query(%Ecto.Query{} = queryable) do
  #   %{from: %Ecto.Query.FromExpr{source: {_, model}}, select: selects, wheres: wheres} =
  #     Map.from_struct(queryable)

  #   {cql_where, params} = build_where(wheres)
  #   cql_return = build_return(selects)

  #   cql = NodeCql.build_query(model.__schema__(:source), cql_where, cql_return)

  #   {cql, params}
  # end

  # defp build_return(nil) do
  #   "n"
  # end

  # defp build_return(%Ecto.Query.SelectExpr{expr: expression}) do
  #   str =
  #     expression
  #     |> Macro.to_string()
  #     |> String.replace("&0", "n")
  #     |> String.replace("n.id", "n.nodeId")

  #   Regex.replace(~r/\[|\]|\(|\)/, str, "")
  # end

  # defp build_where([]) do
  #   {"", %{}}
  # end

  # defp build_where([%Ecto.Query.BooleanExpr{expr: expression, params: ecto_params}]) do
  #   {cql_where, unbound_params, _} = do_build_where(expression)

  #   # Merge unbound params and params explicitly bind in Query
  #   params =
  #     ecto_params
  #     |> Enum.into(%{}, fn {value, {0, field}} ->
  #       {field, value}
  #     end)
  #     |> Map.merge(unbound_params)

  #   {cql_where, params}
  # end

  # defp do_build_where(expression, inc \\ 0)

  # defp do_build_where(
  #        {operator, _, [_, %Ecto.Query.Tagged{type: {_, field}, value: value}]},
  #        inc
  #      ) do
  #   field_name =
  #     field
  #     |> format_field()
  #     |> Atom.to_string()

  #   cql = "n.#{field_name} #{format_operator(operator)} {param_#{inc}}"

  #   params =
  #     %{"param_#{inc}" => value}
  #     |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
  #     |> Map.new()

  #   {cql, params, inc}
  # end

  # defp do_build_where(
  #        {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, {:^, _, _}]},
  #        inc
  #      ) do
  #   field_name =
  #     field
  #     |> format_field()
  #     |> Atom.to_string()

  #   cql = "n.#{field_name} #{format_operator(operator)} {#{field_name}}"
  #   {cql, %{}, inc}
  # end

  # defp do_build_where({operation, _, [arg1, arg2]}, inc) do
  #   {cql1, params1, inc} = do_build_where(arg1, inc + 1)
  #   {cql2, params2, _} = do_build_where(arg2, inc + 1)

  #   cql = "#{cql1} #{Atom.to_string(operation)} #{cql2}"
  #   params = Map.merge(params1, params2)
  #   {cql, params, inc + 1}
  # end

  # defp format_operator(:==) do
  #   "="
  # end

  # defp format_operator(operator) when operator in [:>, :>=, :<, :<=] do
  #   Atom.to_string(operator)
  # end

  # defp to_struct(result, struct_model) do
  #   props =
  #     result.properties
  #     |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
  #     |> Map.new()
  #     |> manage_id()

  #   struct(struct_model, props)
  # end

  @doc """
  Launch the given query with params on database.

  Returns all found results, on raise a `Bolt.Sips.Exception` in case of error.

  As database errors should not be silently ignored, a wrong query will crash.

  ### Example
      EctoNeo4j.Repo.query("MATCH (n:Post {uuid: {uuid}}", %{uuid: "unique_id"})
  """
  def query(cql, params \\ %{}, opts \\ []) do
    do_query(cql, params, opts)
  end

  def query!(cql, params \\ %{}, opts \\ []) do
    case do_query(cql, params, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp do_query(cql, params, _opts) do
    Bolt.Sips.transaction(Bolt.Sips.conn(), fn conn ->
      Bolt.Sips.query!(conn, cql, params)
    end)
  end

  # @spec manage_id(map()) :: map()
  # defp manage_id(%{nodeId: node_id} = data) do
  #   data
  #   |> Map.put(:id, node_id)
  #   |> Map.drop([:node_id])
  # end

  # defp manage_id(data), do: data

  # defp format_field(:id), do: :nodeId
  # defp format_field(field), do: field

  def stream(_, _, _, _, _, _opts \\ []) do
    raise(
      ArgumentError,
      "stream/6 is not supported by adapter, use EctoMnesia.Table.Stream.new/2 instead"
    )
  end
end
