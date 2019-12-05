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
    defstruct [:index, :variable, :labels]

    @type t :: %__MODULE__{
            index: integer(),
            variable: String.t(),
            labels: [String.t()]
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
    defstruct [:operator, :field, :is_distinct?]

    @type t :: %__MODULE__{
            operator: atom(),
            field: FieldExpr.t(),
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

  defstruct [:operation, :match, :where, :return, :set, :params, :order_by, :skip, :limit]

  @type t :: %__MODULE__{
          operation: atom(),
          match: [String.t()],
          where: Ecto.Adapters.Neo4j.Condition.t(),
          set: [SetExpr.t()],
          return: ReturnExpr.t(),
          params: map(),
          order_by: [OrderExpr.t()],
          skip: nil | integer(),
          limit: nil | integer()
        }

  alias Ecto.Adapters.Neo4j.Query

  def new(operation \\ :match) do
    %Query{
      operation: operation,
      match: [],
      where: nil,
      return: [],
      set: [],
      params: %{},
      order_by: [],
      skip: nil,
      limit: nil
    }
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

  @spec skip(Query.t(), nil | integer()) :: Query.t()
  def skip(query, nil) do
    query
  end

  def skip(query, limit) do
    %{query | limit: limit}
  end

  def to_string(query) do
    match =
      query.match
      |> MapSet.new()
      |> MapSet.to_list()
      |> stringify_match()

    where = stringify_where(query.where)
    return = stringify_return(query.return)
    order_by = stringify_order_by(query.order_by)
    limit = stringify_limit(query.limit)

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
      if query.skip do
        """
        SKIP #{stringify_skip(query.skip)}
        """
      end

    cql_limit =
      if String.length(limit) > 0 do
        """
        LIMIT #{limit}
        """
      end

    cql_delete =
      if query.operation == :delete_all do
        deletes =
          query.match
          |> MapSet.new()
          |> MapSet.to_list()
          |> stringify_delete()

        """
        DETACH DELETE
          #{deletes}
        """
      end

    cql = """
    MATCH
      #{match}
    #{cql_where}
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

  def stringify_delete(matches) do
    Enum.map(matches, fn %{variable: variable} ->
      variable
    end)
    |> Enum.join(", ")
  end

  def stringify_where(condition) do
    Ecto.Adapters.Neo4j.Condition.stringify_condition(condition)
  end

  def stringify_return(%ReturnExpr{fields: fields, is_distinct?: is_distinct?}) do
    distinct =
      if is_distinct? do
        "DISTINCT "
      end

    fields_cql =
      Enum.map(fields, fn
        nil ->
          "NULL"

        %NodeExpr{variable: variable} ->
          variable

        %AggregateExpr{operator: operator, field: field, is_distinct?: is_distinct?} ->
          cql_distinct =
            if is_distinct? do
              "DISTINCT "
            end

          "#{format_operator(operator)}(#{cql_distinct}#{stringify_field(field)})"

        %FieldExpr{} = field ->
          stringify_field(field)
      end)
      |> Enum.join(", ")

    "#{distinct}#{fields_cql}"
  end

  def stringify_set(%SetExpr{field: field, increment: increment}) when not is_nil(increment) do
    "#{stringify_field(field)} = #{stringify_field(field)} + {#{increment}}"
  end

  def stringify_set(%SetExpr{field: field, value: value}) do
    "#{stringify_field(field)} = {#{value}}"
  end

  def stringify_order_by(order_bys) when is_list(order_bys) do
    Enum.map(order_bys, fn %OrderExpr{order: order, field: field} ->
      stringify_field(field) <> " " <> format_operator(order)
    end)
    |> Enum.join(", ")
  end

  def stringify_limit(limit) when is_integer(limit) do
    Integer.to_string(limit)
  end

  def stringify_limit(nil) do
    ""
  end

  def stringify_skip(skip) when is_integer(skip) do
    Integer.to_string(skip)
  end

  def stringify_skip(nil) do
    ""
  end

  def stringify_field(%FieldExpr{variable: variable, name: field, alias: alias}) do
    field_name = Atom.to_string(field)

    case alias do
      nil -> "#{variable}.#{field_name}"
      field_alias -> "#{variable}.#{field_name} AS #{field_alias}"
    end
  end

  defp format_operator(operator) do
    operator
    |> Atom.to_string()
    |> String.upcase()
  end
end
