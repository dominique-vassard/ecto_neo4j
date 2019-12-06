defmodule Ecto.Adapters.Neo4j.Query do
  defmodule Str do
    defstruct [:match, :where, :return, :params]

    @type t :: %__MODULE__{
            match: String.t(),
            where: String.t(),
            return: String.t(),
            params: map()
          }
  end

  defmodule NodeExpr do
    defstruct [:index, :variable, :labels, :alias]

    @type t :: %__MODULE__{
            index: integer(),
            variable: String.t(),
            labels: [String.t()],
            alias: nil | String.t()
          }
  end

  defmodule RelationshipExpr do
    defstruct [:index, :variable, :start_index, :end_index, :type]

    @type t :: %__MODULE__{
            index: integer(),
            variable: String.t(),
            start_index: integer(),
            end_index: integer(),
            type: String.t()
          }
  end

  defmodule FieldExpr do
    defstruct [:alias, :variable, :name]

    @type t :: %__MODULE__{
            alias: String.t(),
            variable: String.t(),
            name: atom()
          }
  end

  defmodule ReturnExpr do
    defstruct [:fields, is_distinct?: false]

    @type t :: %__MODULE__{
            fields: [nil | FieldExpr.t() | AggregateExpr.t() | NodeExpr.t()],
            is_distinct?: boolean()
          }
  end

  defmodule OrderExpr do
    defstruct [:field, :order]

    @type t :: %__MODULE__{
            field: FieldExpr.t(),
            order: atom()
          }
  end

  defmodule AggregateExpr do
    defstruct [:alias, :operator, :field, :entity, :is_distinct?]

    @type t :: %__MODULE__{
            alias: String.t(),
            operator: atom(),
            field: FieldExpr.t(),
            entity: NodeExpr.t() | RelationshipExpr.t(),
            is_distinct?: boolean()
          }
  end

  defmodule SetExpr do
    defstruct [:field, :value, :increment]

    @type t :: %__MODULE__{
            field: FieldExpr.t(),
            value: any(),
            increment: integer()
          }
  end

  defmodule BatchExpr do
    defstruct [:with, :skip, :limit]

    @type t :: %__MODULE__{
            with: NodeExpr.t(),
            skip: nil | integer | atom,
            limit: nil | integer | atom
          }
  end

  defmodule Batch do
    defstruct [:is_batch?, :type, :chunk_size, :__expr]

    @type t :: %__MODULE__{
            is_batch?: boolean,
            type: :basic | :with_skip,
            chunk_size: integer(),
            __expr: nil | BatchExpr.t()
          }
  end

  defstruct [
    :operation,
    :match,
    :where,
    :return,
    :set,
    :params,
    :order_by,
    :skip,
    :limit,
    :batch
  ]

  @type t :: %__MODULE__{
          operation: atom(),
          match: [String.t()],
          where: nil | Ecto.Adapters.Neo4j.Condition.t(),
          set: [SetExpr.t()],
          return: nil | ReturnExpr.t(),
          params: map(),
          order_by: [OrderExpr.t()],
          skip: nil | integer() | atom(),
          limit: nil | integer() | atom(),
          batch: Batch.t()
        }

  alias Ecto.Adapters.Neo4j.Query

  @chunk_size Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, chunk_size: 10_000)
              |> Keyword.get(:chunk_size)
  @is_batch? Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, batch: false)
             |> Keyword.get(:batch)

  @spec new(atom()) :: Query.t()
  def new(operation \\ :match) do
    %Query{
      operation: operation,
      match: [],
      where: nil,
      set: [],
      return: nil,
      params: %{},
      order_by: [],
      skip: nil,
      limit: nil,
      batch: %Batch{
        is_batch?: @is_batch?,
        type: :basic,
        chunk_size: @chunk_size
      }
    }
  end

  @spec batch(Query.t(), Batch.t()) :: Query.t()
  def batch(query, %Batch{} = batch_opt) do
    batch =
      case query.operation in [:update, :update_all] do
        true ->
          %{batch_opt | type: :with_skip}

        _ ->
          %{batch_opt | type: :basic}
      end

    %{query | batch: Map.merge(query.batch, batch)}
  end

  def match(query, match) when is_list(match) do
    %{query | match: query.match ++ match}
  end

  def match(query, match) when is_binary(match) do
    match(query, [match])
  end

  def where(%Query{where: nil} = query, %Ecto.Adapters.Neo4j.Condition{} = condition) do
    %{query | where: condition}
  end

  def where(%Query{where: query_cond} = query, %Ecto.Adapters.Neo4j.Condition{} = condition) do
    new_condition = %Ecto.Adapters.Neo4j.Condition{
      operator: :and,
      conditions: [
        query_cond,
        condition
      ]
    }

    %{query | where: new_condition}
  end

  def where(query, nil) do
    query
  end

  def set(query, sets) when is_list(sets) do
    %{query | set: query.set ++ sets}
  end

  def set(query, nil) do
    query
  end

  def return(query, %ReturnExpr{} = return) do
    %{query | return: return}
  end

  def params(query, %{} = params) do
    %{query | params: Map.merge(query.params, params)}
  end

  def order_by(query, order_by) do
    %{query | order_by: order_by}
  end

  @spec limit(Query.t(), nil | integer()) :: Query.t()
  def limit(query, nil) do
    query
  end

  def limit(query, limit) do
    %{query | limit: limit}
  end

  @spec skip(Query.t(), nil | integer() | atom()) :: Query.t()
  def skip(query, nil) do
    query
  end

  def skip(query, skip) do
    %{query | skip: skip}
  end

  @spec batchify_query(Query.t()) :: Query.t()
  def batchify_query(%Query{batch: %{is_batch?: true} = batch, operation: operation} = query)
      when operation in [:update, :update_all, :delete, :delete_all] do
    node = List.first(query.match)

    return = %ReturnExpr{
      fields: [
        %AggregateExpr{
          alias: "nb_touched_nodes",
          operator: :count,
          entity: node
        }
      ]
    }

    batch_with = %ReturnExpr{
      fields: [
        Map.put(node, :alias, node.variable)
      ]
    }

    batch_skip =
      if operation in [:update, :update_all] do
        :skip
      end

    batch_expr = %BatchExpr{
      with: batch_with,
      skip: batch_skip,
      limit: :limit
    }

    query
    |> Query.return(return)
    |> Query.skip(nil)
    |> Query.limit(nil)
    |> Query.order_by([])
    |> Query.params(%{limit: batch.chunk_size})
    |> Query.batch(%{batch | __expr: batch_expr})
  end

  def batchify_query(query) do
    query
  end

  def to_string(bare_query) do
    query = batchify_query(bare_query)

    match =
      query.match
      |> MapSet.new()
      |> MapSet.to_list()
      |> stringify_match()

    where = stringify_where(query.where)
    return = stringify_return(query.return)
    order_by = stringify_order_by(query.order_by)
    limit = stringify_limit(query.limit)
    skip = stringify_skip(query.skip)
    cql_batch = stringify_batch(query.batch)

    delete =
      if query.operation == :delete_all do
        query.match
        |> MapSet.new()
        |> MapSet.to_list()
        |> stringify_delete()
      else
        ""
      end

    cql_set =
      if length(query.set) > 0 do
        sets =
          query.set
          |> Enum.map(&stringify_set/1)
          |> Enum.join(",\n  ")

        """
        SET
          #{sets}
        """
      end

    cql_where =
      if String.length(where) > 0 do
        """
        WHERE
          #{where}
        """
      end

    cql_order_by =
      if String.length(order_by) > 0 do
        """
        ORDER BY
          #{order_by}
        """
      end

    cql_skip =
      if String.length(skip) > 0 do
        """
        SKIP #{skip}
        """
      end

    cql_limit =
      if String.length(limit) > 0 do
        """
        LIMIT #{limit}
        """
      end

    cql_delete =
      if String.length(delete) > 0 do
        """
        DETACH DELETE
          #{delete}
        """
      end

    cql = """
    MATCH
      #{match}
    #{cql_where}
    #{cql_batch}
    #{cql_delete}
    #{cql_set}
    RETURN
      #{return}
    #{cql_order_by}
    #{cql_skip}
    #{cql_limit}
    """

    {cql, query.params}
  end

  def stringify_match(matches) do
    Enum.map(matches, &stringify_match_entity/1)
    |> Enum.join(",\n")
  end

  defp stringify_match_entity(%NodeExpr{variable: variable, labels: [label]}) do
    "(#{variable}:#{label})"
  end

  defp stringify_match_entity(%RelationshipExpr{
         start_index: start_variable,
         end_index: end_variable,
         type: rel_type,
         variable: variable
       }) do
    "(#{start_variable})-[#{variable}:#{rel_type}]->(#{end_variable})"
  end

  @spec stringify_delete([]) :: String.t()
  def stringify_delete(matches) do
    Enum.map(matches, fn %{variable: variable} ->
      variable
    end)
    |> Enum.join(", ")
  end

  @spec stringify_where(nil | Ecto.Adapters.Neo4j.Condition.t()) :: String.t()
  def stringify_where(condition) do
    Ecto.Adapters.Neo4j.Condition.stringify_condition(condition)
  end

  @spec stringify_return(ReturnExpr.t()) :: String.t()
  def stringify_return(%ReturnExpr{fields: fields, is_distinct?: is_distinct?}) do
    distinct =
      if is_distinct? do
        "DISTINCT "
      end

    fields_cql =
      Enum.map(fields, fn
        nil ->
          "NULL"

        %NodeExpr{} = node ->
          stringify_node(node)

        %AggregateExpr{} = aggregate ->
          stringify_aggregate(aggregate)

        %FieldExpr{} = field ->
          stringify_field(field)
      end)
      |> Enum.join(", ")

    "#{distinct}#{fields_cql}"
  end

  @spec stringify_set(SetExpr.t()) :: String.t()
  def stringify_set(%SetExpr{field: field, increment: increment}) when not is_nil(increment) do
    "#{stringify_field(field)} = #{stringify_field(field)} + {#{increment}}"
  end

  def stringify_set(%SetExpr{field: field, value: value}) do
    "#{stringify_field(field)} = {#{value}}"
  end

  def stringify_batch(%Batch{is_batch?: true, __expr: expression}) do
    skip = stringify_skip(expression.skip)

    cql_skip =
      if String.length(skip) > 0 do
        "SKIP #{skip}"
      end

    """
    WITH
      #{stringify_return(expression.with)}
    #{cql_skip}
    LIMIT #{stringify_limit(expression.limit)}
    """
  end

  def stringify_batch(_) do
    ""
  end

  @spec stringify_order_by([]) :: String.t()
  def stringify_order_by(order_bys) when is_list(order_bys) do
    Enum.map(order_bys, fn %OrderExpr{order: order, field: field} ->
      stringify_field(field) <> " " <> format_operator(order)
    end)
    |> Enum.join(", ")
  end

  @spec stringify_limit(nil | integer | atom) :: String.t()
  def stringify_limit(limit) when is_integer(limit) do
    Integer.to_string(limit)
  end

  def stringify_limit(nil) do
    ""
  end

  def stringify_limit(limit) when is_atom(limit) do
    "{#{Atom.to_string(limit)}}"
  end

  @spec stringify_skip(nil | integer | atom()) :: String.t()
  def stringify_skip(skip) when is_integer(skip) do
    Integer.to_string(skip)
  end

  def stringify_skip(nil) do
    ""
  end

  def stringify_skip(skip) when is_atom(skip) do
    "{#{Atom.to_string(skip)}}"
  end

  @spec stringify_field(FieldExpr.t()) :: String.t()
  def stringify_field(%FieldExpr{variable: variable, name: field, alias: alias}) do
    field_name = Atom.to_string(field)

    case alias do
      nil -> "#{variable}.#{field_name}"
      field_alias -> "#{variable}.#{field_name} AS #{field_alias}"
    end
  end

  def stringify_node(%NodeExpr{alias: node_alias, variable: variable})
      when not is_nil(node_alias) do
    "#{variable} AS #{node_alias}"
  end

  def stringify_node(%NodeExpr{variable: variable}) do
    variable
  end

  @spec stringify_aggregate(AggregateExpr.t()) :: String.t()
  def stringify_aggregate(%AggregateExpr{field: field} = aggregate) when not is_nil(field) do
    do_stringify_aggregate(aggregate, stringify_field(field))
  end

  def stringify_aggregate(%AggregateExpr{entity: %{variable: variable}} = aggregate) do
    do_stringify_aggregate(aggregate, variable)
  end

  defp do_stringify_aggregate(
         %AggregateExpr{alias: agg_alias, operator: operator, is_distinct?: is_distinct?},
         target
       ) do
    cql_distinct =
      if is_distinct? do
        "DISTINCT "
      end

    cql_alias =
      unless is_nil(agg_alias) do
        " AS #{agg_alias}"
      end

    "#{format_operator(operator)}(#{cql_distinct}#{target})#{cql_alias}"
  end

  defp format_operator(operator) do
    operator
    |> Atom.to_string()
    |> String.upcase()
  end
end
