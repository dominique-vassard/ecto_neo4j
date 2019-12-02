defmodule Ecto.Adapters.Neo4j.Query do
  @moduledoc """
  %Query{
    match: [
      %NodeExpr{
        labels: [],

      }
    ]
  }
  """
  defstruct [:match, :where, :return, :params]

  @type t :: %__MODULE__{
          match: [String.t()],
          where: [Ecto.Adapters.Neo4j.Condition.t()],
          return: [String.t()],
          params: map()
        }

  alias Ecto.Adapters.Neo4j.Query

  defmodule Str do
    defstruct [:match, :where, :return, :params]
  end

  defmodule NodeExpr do
    defstruct [:index, :variable, :labels]
  end

  defmodule RelationshipExpr do
    defstruct [:index, :variable, :start_index, :end_index, :type]
  end

  defmodule ReturnExpr do
    defstruct [:fields, is_distinct?: false]
  end

  defmodule FieldExpr do
    defstruct [:alias, :variable, :name]
  end

  def new() do
    %Query{
      match: [],
      where: nil,
      return: [],
      params: %{}
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

  def where(query, []) do
    query
  end

  def return(query, %ReturnExpr{} = return) do
    %{query | return: return}
  end

  def params(query, %{} = params) do
    %{query | params: Map.merge(query.params, params)}
  end

  def to_string(query) do
    match =
      query.match
      |> MapSet.new()
      |> MapSet.to_list()
      |> stringify_match()

    where = stringify_where(query.where)
    return = stringify_return(query.return)

    cql = """
    MATCH
      #{match}
    WHERE
      #{where}
    RETURN
      #{return}
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

  def stringify_where(condition) do
    # conditions
    # |> Enum.map(&Ecto.Adapters.Neo4j.Condition.stringify_condition/1)
    # |> Enum.map(fn condition ->
    #   IO.inspect(condition, label: "TREATING")

    Ecto.Adapters.Neo4j.Condition.stringify_condition(condition)
    |> IO.inspect(label: "RES ----->")

    # end)
    # |> Enum.join(" AND ")
    # |> IO.inspect(label: "WHERE")
  end

  def stringify_return(%ReturnExpr{fields: fields, is_distinct?: is_distinct?}) do
    distinct =
      if is_distinct? do
        "DISTINCT "
      end

    fields_cql =
      Enum.map(fields, fn %FieldExpr{variable: variable, name: field} = field_data ->
        field_name = Atom.to_string(field)

        case Map.get(field_data, :alias) do
          nil -> "#{variable}.#{field_name}"
          field_alias -> "#{variable}.#{field_name} AS #{field_alias}"
        end
      end)
      |> Enum.join(", ")

    "#{distinct}#{fields_cql}"
  end
end
