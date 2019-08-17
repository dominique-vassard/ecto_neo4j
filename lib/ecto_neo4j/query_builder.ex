defmodule EctoNeo4j.QueryBuilder do
  import Ecto.Query
  alias EctoNeo4j.Cql.Node, as: NodeCql

  @valid_operators [:==, :in, :>, :>=, :<, :<=]
  def build(queryable_or_schema, sources, opts \\ [])

  def build(%Ecto.Query{} = query, sources, opts) do
    {source, _schema} = query.from.source
    wheres = query.wheres

    cql_return = build_return(query.select.fields)

    {cql_where, params} = build_where(wheres, sources)

    cql = NodeCql.build_query(source, cql_where, cql_return)

    {cql, params}
  end

  def build(schema, sources, opts) do
    query = from(s in schema)
    build(query, sources, opts)
  end

  defp build_return(select_fields) do
    select_fields
    |> Enum.map(&resolve_field_name/1)
    |> Enum.join(", ")
  end

  defp resolve_field_name({{:., _, [{:&, [], [0]}, field_name]}, [], []}) do
    "n." <> Atom.to_string(field_name)
  end

  # defp build_where(%Ecto.Query.BooleanExpr{expr: expr}) do
  #   do_build_where(expr)
  # end

  defp build_where([%Ecto.Query.BooleanExpr{expr: expression, params: ecto_params}], sources) do
    {cql_where, unbound_params, _} = do_build_where(expression, sources)

    ecto_params = ecto_params || []
    # Merge unbound params and params explicitly bind in Query
    params =
      ecto_params
      |> Enum.into(%{}, fn {value, {0, field}} ->
        {field, value}
      end)
      |> Map.merge(unbound_params)

    {cql_where, params}
  end

  defp build_where([], _) do
    {"", %{}}
  end

  defp do_build_where(expression, sources, inc \\ 0)

  defp do_build_where(
         {operator, _, [_, %Ecto.Query.Tagged{type: {_, field}, value: value}]},
         sources,
         inc
       ) do
    cql = "n.#{format_field(field)} #{format_operator(operator)} {param_#{inc}}"

    params =
      %{"param_#{inc}" => value}
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    {cql, params, inc}
  end

  # defp do_build_where(
  #        {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, {:^, _, _}]},
  #        sources,
  #        inc
  #      ) do
  #   cql = "n.#{format_field(field)} #{format_operator(operator)} {#{format_field(field)}}"
  #   {cql, %{}, inc}
  # end

  defp do_build_where(
         {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, {:^, _, [s_index, s_length]}]},
         sources,
         inc
       ) do
    cql = "n.#{format_field(field)} #{format_operator(operator)} {#{format_field(field)}}"

    params =
      %{}
      |> Map.put(String.to_atom(format_field(field)), Enum.slice(sources, s_index, s_length))

    {cql, params, inc}
  end

  defp do_build_where(
         {operator, _, [{{:., _, [{:&, _, _}, field]}, [], []}, value]},
         sources,
         inc
       ) do
    params =
      %{"param_#{inc}" => value}
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    cql = "n.#{format_field(field)} #{format_operator(operator)} {param_#{inc}}"
    {cql, params, inc}
  end

  defp do_build_where({operator, _, [arg]}, sources, inc) do
    {cql_sub, params, inc} = do_build_where(arg, sources, inc + 1)
    cql = "#{Atom.to_string(operator)} (#{cql_sub})"

    {cql, params, inc + 1}
  end

  defp do_build_where({operation, _, [arg1, arg2]}, sources, inc) do
    {cql1, params1, inc} = do_build_where(arg1, sources, inc + 1)
    {cql2, params2, _} = do_build_where(arg2, sources, inc + 1)

    cql = "#{cql1} #{Atom.to_string(operation)} #{cql2}"
    params = Map.merge(params1, params2)
    {cql, params, inc + 1}
  end

  defp format_operator(:==) do
    "="
  end

  defp format_operator(:in) do
    "IN"
  end

  defp format_operator(operator) when operator in @valid_operators do
    Atom.to_string(operator)
  end

  defp format_field(:id), do: format_field(:nodeId)
  defp format_field(field), do: field |> Atom.to_string()
end
