defmodule Ecto.Adapters.Neo4j.Query do
  defmodule NodeExpr do
    defstruct [:index, :variable, :labels, :alias]

    @type t :: %__MODULE__{
            index: nil | integer(),
            variable: String.t(),
            labels: nil | [String.t()],
            alias: nil | String.t()
          }
  end

  defmodule RelationshipExpr do
    defstruct [:index, :variable, :start, :end, :type]

    @type t :: %__MODULE__{
            index: nil | integer(),
            variable: String.t(),
            start: NodeExpr.t(),
            end: NodeExpr.t(),
            type: String.t()
          }
  end

  @type entity_expr :: NodeExpr.t() | RelationshipExpr.t()

  defmodule FieldExpr do
    defstruct [:alias, :variable, :name]

    @type t :: %__MODULE__{
            alias: String.t(),
            variable: String.t(),
            name: atom()
          }
  end

  defmodule ValueExpr do
    defstruct [:name, :variable, :value]

    @type t :: %__MODULE__{
            name: atom(),
            variable: String.t(),
            value: any
          }
  end

  defmodule OrderExpr do
    defstruct [:field, order: :asc]

    @type t :: %__MODULE__{
            field: FieldExpr.t(),
            order: atom()
          }
  end

  defmodule AggregateExpr do
    defstruct [:alias, :operator, :field, :entity, is_distinct?: false]

    @type t :: %__MODULE__{
            alias: String.t(),
            operator: atom(),
            field: nil | FieldExpr.t(),
            entity: nil | NodeExpr.t() | RelationshipExpr.t(),
            is_distinct?: boolean()
          }
  end

  defmodule CollectExpr do
    defstruct [:alias, :variable]

    @type t :: %__MODULE__{
            alias: String.t(),
            variable: String.t()
          }
  end

  defmodule ReturnExpr do
    defstruct [:fields, is_distinct?: false]

    @type t :: %__MODULE__{
            fields: [
              nil
              | FieldExpr.t()
              | AggregateExpr.t()
              | NodeExpr.t()
              | CollectExpr.t()
              | ValueExpr.t()
            ],
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

  defmodule MergeExpr do
    defstruct [:expr, on_create: [], on_update: []]

    @type t :: %__MODULE__{
            expr: Ecto.Adapters.Neo4j.Query.entity_expr(),
            on_create: [SetExpr.t()],
            on_update: [SetExpr.t()]
          }
  end

  defmodule BatchExpr do
    defstruct [:with, :skip, :limit]

    @type t :: %__MODULE__{
            with: ReturnExpr.t(),
            skip: nil | integer | atom,
            limit: nil | integer | atom
          }
  end

  defmodule Batch do
    defstruct [:type, :chunk_size, :__expr, is_batch?: false]

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
    :merge,
    :delete,
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
          match: [entity_expr],
          merge: [MergeExpr.t()],
          delete: [entity_expr],
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
      merge: [],
      where: nil,
      set: [],
      delete: [],
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

  @spec match(Query.t(), [entity_expr]) :: Query.t()
  def match(query, match) when is_list(match) do
    %{query | match: query.match ++ match}
  end

  @spec merge(Query.t(), [MergeExpr.t()]) :: Query.t()
  def merge(query, merge) when is_list(merge) do
    %{query | merge: query.merge ++ merge}
  end

  @spec delete(Query.t(), [entity_expr]) :: Query.t()
  def delete(query, delete) when is_list(delete) do
    %{query | delete: query.delete ++ delete}
  end

  @spec where(Query.t(), nil | Ecto.Adapters.Neo4j.Condition.t()) :: Query.t()
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

  @spec set(Query.t(), nil | [SetExpr.t()]) :: Query.t()
  def set(query, sets) when is_list(sets) do
    %{query | set: query.set ++ sets}
  end

  def set(query, nil) do
    query
  end

  @spec return(Query.t(), ReturnExpr.t()) :: Query.t()
  def return(query, %ReturnExpr{} = return) do
    %{query | return: return}
  end

  @spec params(Query.t(), map) :: Query.t()
  def params(query, %{} = params) do
    %{query | params: Map.merge(query.params, params)}
  end

  @spec order_by(Query.t(), [OrderExpr.t()]) :: Query.t()
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
  def batchify_query(%Query{batch: %{is_batch?: true}, operation: operation} = query)
      when operation in [:update, :update_all, :delete, :delete_all] do
    node = List.first(query.match)

    return = %ReturnExpr{
      fields: [
        %AggregateExpr{
          alias: "nb_touched_nodes",
          operator: :count,
          entity: node,
          is_distinct?: false
        }
      ],
      is_distinct?: false
    }

    batch_with = %ReturnExpr{
      fields: [
        Map.put(node, :alias, node.variable)
      ],
      is_distinct?: false
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
    |> Query.params(%{limit: query.batch.chunk_size})
    |> Query.batch(%{query.batch | __expr: batch_expr})
  end

  def batchify_query(query) do
    query
  end

  @spec to_string(Query.t()) :: {String.t(), map}
  def to_string(bare_query) do
    query = batchify_query(bare_query)

    match =
      query.match
      |> MapSet.new()
      |> MapSet.to_list()
      |> stringify_match()

    cql_merge = stringify_merges(query.merge)
    where = stringify_where(query.where)
    return = stringify_return(query.return)
    order_by = stringify_order_by(query.order_by)
    limit = stringify_limit(query.limit)
    skip = stringify_skip(query.skip)
    cql_batch = stringify_batch(query.batch)

    # TODO: unify in query.delete
    delete =
      cond do
        query.operation == :delete_all ->
          stringify_delete(query.match)

        length(query.delete) > 0 ->
          stringify_delete(query.delete)

        true ->
          ""
      end

    cql_match =
      if String.length(match) > 0 do
        """
        MATCH
          #{match}
        """
      end

    cql_return =
      if String.length(return) > 0 do
        """
        RETURN
          #{return}
        """
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
    #{cql_match}
    #{cql_where}
    #{cql_merge}
    #{cql_batch}
    #{cql_delete}
    #{cql_set}
    #{cql_return}
    #{cql_order_by}
    #{cql_skip}
    #{cql_limit}
    """

    {cql, query.params}
  end

  @spec stringify_match([entity_expr]) :: String.t()
  def stringify_match(matches) do
    Enum.map(matches, &stringify_match_entity/1)
    |> Enum.join(",\n")
  end

  @spec stringify_match_entity(entity_expr) :: String.t()
  defp stringify_match_entity(%NodeExpr{variable: variable, labels: [label]}) do
    "(#{variable}:#{label})"
  end

  defp stringify_match_entity(%NodeExpr{variable: variable}) do
    "(#{variable})"
  end

  defp stringify_match_entity(%RelationshipExpr{
         start: start_node,
         end: end_node,
         type: rel_type,
         variable: variable
       }) do
    cql_type =
      unless is_nil(rel_type) do
        ":#{rel_type}"
      end

    stringify_match_entity(start_node) <>
      "-[#{variable}#{cql_type}]->" <> stringify_match_entity(end_node)
  end

  @spec stringify_merges([MergeExpr.t()]) :: String.t()
  def stringify_merges(merges) do
    merges
    |> Enum.map(&stringify_merge/1)
    |> Enum.join(" \n")
  end

  @spec stringify_merge(nil | MergeExpr.t()) :: String.t()
  defp stringify_merge(%MergeExpr{expr: entity, on_create: create_sets, on_update: update_sets}) do
    cql_create =
      if length(create_sets) > 0 do
        sets =
          create_sets
          |> Enum.map(&stringify_set/1)
          |> Enum.join(",\n  ")

        """
        ON CREATE SET
          #{sets}
        """
      end

    cql_update =
      if length(update_sets) > 0 do
        sets =
          update_sets
          |> Enum.map(&stringify_set/1)
          |> Enum.join(",\n  ")

        """
        ON UPDATE SET
          #{sets}
        """
      end

    """
    MERGE
      #{stringify_match_entity(entity)}
    #{cql_create}
    #{cql_update}
    """
  end

  defp stringify_merge(_) do
    ""
  end

  @spec stringify_delete([]) :: String.t()
  def stringify_delete(deletes) do
    Enum.map(deletes, fn %{variable: variable} ->
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

        %RelationshipExpr{} = relationship ->
          stringify_relationship(relationship)

        %AggregateExpr{} = aggregate ->
          stringify_aggregate(aggregate)

        %CollectExpr{} = collect ->
          stringify_collect(collect)

        %FieldExpr{} = field ->
          stringify_field(field)

        %ValueExpr{} = value ->
          stringify_value(value)
      end)
      |> Enum.join(", ")

    "#{distinct}#{fields_cql}"
  end

  def stringify_return(_) do
    ""
  end

  @spec stringify_set(SetExpr.t()) :: String.t()
  def stringify_set(%SetExpr{field: field, increment: increment}) when not is_nil(increment) do
    "#{stringify_field(field)} = #{stringify_field(field)} + {#{increment}}"
  end

  def stringify_set(%SetExpr{field: field, value: value}) do
    "#{stringify_field(field)} = {#{value}}"
  end

  @spec stringify_batch(Batch.t()) :: String.t()
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

  @spec stringify_node(NodeExpr.t()) :: String.t()
  def stringify_node(%NodeExpr{alias: node_alias, variable: variable})
      when not is_nil(node_alias) do
    "#{variable} AS #{node_alias}"
  end

  def stringify_node(%NodeExpr{variable: variable}) do
    variable
  end

  @spec stringify_relationship(RelationshipExpr.t()) :: String.t()
  def stringify_relationship(%RelationshipExpr{variable: variable}) do
    variable
  end

  @spec stringify_aggregate(AggregateExpr.t()) :: String.t()
  def stringify_aggregate(%AggregateExpr{field: field} = aggregate) when not is_nil(field) do
    do_stringify_aggregate(aggregate, stringify_field(field))
  end

  def stringify_aggregate(%AggregateExpr{entity: %{variable: variable}} = aggregate) do
    do_stringify_aggregate(aggregate, variable)
  end

  @spec do_stringify_aggregate(AggregateExpr.t(), String.t()) :: String.t()
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

  @spec stringify_collect(CollectExpr.t()) :: String.t()
  def stringify_collect(%CollectExpr{alias: collect_alias, variable: variable}) do
    "COLLECT (#{variable}) AS #{collect_alias}"
  end

  @spec stringify_value(ValueExpr.t()) :: String.t()
  def stringify_value(%ValueExpr{variable: variable, name: name, value: value}) do
    "#{inspect(value)} AS #{variable}_#{Atom.to_string(name)}"
  end

  @spec format_operator(atom()) :: String.t()
  defp format_operator(operator) do
    operator
    |> Atom.to_string()
    |> String.upcase()
  end
end
