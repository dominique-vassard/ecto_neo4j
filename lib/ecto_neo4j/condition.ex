defmodule Ecto.Adapters.Neo4j.Condition do
  @fields [:source, :field, :operator, :value, :conditions, :join_operator]
  # @enforce_keys @fields
  defstruct @fields

  alias Ecto.Adapters.Neo4j.Condition

  @type t :: %__MODULE__{
          source: String.t(),
          field: atom(),
          operator: atom(),
          value: any(),
          conditions: nil | [Condition.t()],
          join_operator: :and | :or
        }

  @valid_operators [:and, :or, :not, :==, :in, :>, :>=, :<, :<, :min, :max, :count, :sum, :avg]

  def to_relationship_clauses(conditions) do
    conditions =
      to_relationship_clause(conditions, %{match: [], where: nil, params: %{}})
      |> flatten_clauses()

    conditions
  end

  # def to_relationship_format(condition, clauses \\ %{match: [], where: nil, params: %{}})

  # def to_relationship_format(%{operator: :or}, _) do
  #   raise "OR is not supported in joins!"
  # end

  # def to_relationship_format(
  #       %{
  #         source: end_index,
  #         field: field,
  #         operator: :is_nil
  #       },
  #       clauses
  #     )
  #     when not is_nil(field) do
  #   relationship = %Ecto.Adapters.Neo4j.Query.RelationshipExpr{
  #     start_index: "n_0",
  #     end_index: "n_" <> Integer.to_string(end_index),
  #     type: format_relationship(field)
  #   }

  #   condition = %Condition{
  #     operator: :not,
  #     field: relationship
  #   }

  #   new_condition =
  #     case clauses.where do
  #       %Condition{} = prev_condition ->
  #         %Condition{
  #           operator: :and,
  #           conditions: [prev_condition, condition]
  #         }

  #       _ ->
  #         condition
  #     end

  #   %{clauses | where: new_condition}
  # end

  # def to_relationship_format(
  #       %{source: end_index, field: field, operator: :==, value: value},
  #       clauses
  #     )
  #     when not is_nil(field) do
  #   rel_variable = (field |> Atom.to_string()) <> inspect(end_index)

  #   relationship = %Ecto.Adapters.Neo4j.Query.RelationshipExpr{
  #     variable: rel_variable,
  #     start_index: "n_0",
  #     end_index: "n_" <> Integer.to_string(end_index),
  #     type: format_relationship(field)
  #   }

  #   wheres =
  #     value
  #     |> Enum.map(fn {prop, value} ->
  #       key = rel_variable <> "_" <> Atom.to_string(prop)

  #       {%Condition{
  #          source: rel_variable,
  #          field: prop,
  #          operator: :==,
  #          value: key
  #        }, Map.put(%{}, String.to_atom(key), value)}
  #     end)

  #   new_clauses = %{
  #     clauses
  #     | match: clauses.match ++ [relationship]
  #   }

  #   format_relationship_wheres(wheres, new_clauses)
  # end

  # def to_relationship_format(
  #       %{operator: operator, conditions: [condition1, condition2]},
  #       clauses
  #     ) do
  #   c1 = to_relationship_format(condition1, %{match: [], where: nil, params: %{}})

  #   c2 = to_relationship_format(condition2, %{match: [], where: nil, params: %{}})

  #   condition =
  #     join_conditions(c1.where, c2.where, operator)
  #     |> join_conditions(clauses.where)

  #   %{
  #     clauses
  #     | match: clauses.match ++ c1.match ++ c2.match,
  #       where: condition,
  #       params: clauses.params |> Map.merge(c1.params) |> Map.merge(c2.params)
  #   }
  # end

  @spec join_conditions(nil | Condition.t(), nil | Condition.t(), atom) :: nil | Condition.t()
  def join_conditions(condition1, condition2, operator \\ nil)

  def join_conditions(nil, nil, _operator) do
    nil
  end

  def join_conditions(condition1, nil, _operator) do
    condition1
  end

  def join_conditions(nil, condition2, _operator) do
    condition2
  end

  def join_conditions(condition1, condition2, operator) do
    %Condition{
      operator: operator || condition1.join_operator || condition2.join_operator,
      conditions: [condition1, condition2]
    }
  end

  @spec stringify_condition(nil | Condition.t()) :: String.t()
  def stringify_condition(nil) do
    ""
  end

  def stringify_condition(%Condition{operator: operator, conditions: [c1, c2]}) do
    condition1 = stringify_condition(c1)
    condition2 = stringify_condition(c2)

    "#{condition1} #{stringify_operator(operator)} #{condition2}"
  end

  def stringify_condition(%Condition{operator: operator, conditions: condition})
      when not is_nil(condition) do
    str_cond = stringify_condition(condition)

    "#{stringify_operator(operator)} #{str_cond}"
  end

  def stringify_condition(%Condition{
        operator: operator,
        field: %Ecto.Adapters.Neo4j.Query.RelationshipExpr{} = relationship
      }) do
    %{start_index: start_variable, end_index: end_variable, type: rel_type} = relationship
    "#{stringify_operator(operator)} (#{start_variable})-[:#{rel_type}]->(#{end_variable})"
  end

  def stringify_condition(%Condition{
        source: source,
        field: field,
        operator: operator
      })
      when operator == :is_nil do
    "#{source}.#{stringify_field(field)} #{stringify_operator(operator)}"
  end

  def stringify_condition(%Condition{
        source: source,
        field: field,
        operator: operator,
        value: value
      }) do
    "#{source}.#{stringify_field(field)} #{stringify_operator(operator)} {#{value}}"
  end

  defp to_relationship_clause(
         %{
           source: source,
           field: field,
           operator: :is_nil
         },
         clauses
       )
       when not is_nil(field) do
    # """
    # n#{inspect(source)}.#{formated_field} #{stringify_operator(operator)}
    # """
    cql = """
    NOT (n)-[:#{format_relationship(field)}]->(n#{inspect(source)})
    """

    %{clauses | where: clauses.where ++ [cql]}
  end

  defp to_relationship_clause(
         %{source: source, field: field, operator: :==, value: value},
         clauses
       )
       when not is_nil(field) do
    # """
    # n#{inspect(source)}.#{formated_field} #{stringify_operator(operator)} {#{formated_field}}
    # """
    props_data = format_properties(value)

    cql_props =
      if String.length(props_data) > 0 do
        "{" <> props_data <> "}"
      end

    cql = """
        (n)-[:#{format_relationship(field)} #{cql_props}]->(n#{inspect(source)})
    """

    %{
      clauses
      | match: clauses.match ++ [cql],
        params: Map.merge(clauses.params, value)
    }
  end

  defp to_relationship_clause(
         %{operator: operator, conditions: [condition1, condition2]},
         clauses
       ) do
    # """
    # #{to_relationship_clause(condition1)} #{stringify_operator(operator)} #{
    #   to_relationship_clause(condition2)
    # }
    # """
    c1_clauses =
      to_relationship_clause(condition1, %{match: [], where: nil, params: %{}})
      |> flatten_clauses()

    c2_clauses =
      to_relationship_clause(condition2, %{match: [], where: nil, params: %{}})
      |> flatten_clauses()

    match = [c1_clauses.match, c2_clauses.match]

    wheres =
      [c1_clauses.where, c2_clauses.where]
      |> Enum.reject(fn clause -> clause == "" end)

    where =
      case length(wheres) > 1 do
        true ->
          Enum.map(wheres, fn
            clause -> "(" <> clause <> ")"
          end)

        false ->
          wheres
      end
      |> Enum.join(stringify_operator(operator))

    params = Map.merge(c1_clauses.params, c2_clauses.params)

    %{
      clauses
      | match: clauses.match ++ match,
        where: clauses.where ++ [where],
        params: Map.merge(clauses.params, params)
    }
  end

  defp flatten_clauses(%{match: matches, where: wheres, params: params}) do
    match = Enum.join(matches, ", \n")
    where = Enum.join(wheres, " AND ")

    %{
      match: match,
      where: where,
      params: params
    }
  end

  # defp format_relationship_wheres([], clauses) do
  #   clauses
  # end

  # defp format_relationship_wheres(wheres, clauses) do
  #   Enum.reduce(wheres, clauses, fn {where, params}, acc ->
  #     n_cond =
  #       case acc.where do
  #         [] ->
  #           where

  #         condition ->
  #           %Condition{
  #             operator: :and,
  #             conditions: [
  #               condition,
  #               where
  #             ]
  #           }
  #       end

  #     %{
  #       acc
  #       | where: n_cond,
  #         params: Map.merge(acc.params, params)
  #     }
  #   end)
  # end

  @spec stringify_operator(atom) :: String.t()
  defp stringify_operator(:==) do
    "="
  end

  defp stringify_operator(:!=) do
    "<>"
  end

  defp stringify_operator(:in) do
    "IN"
  end

  defp stringify_operator(:is_nil) do
    "IS NULL"
  end

  defp stringify_operator(operator) when operator in @valid_operators do
    Atom.to_string(operator)
  end

  defp format_relationship(rel_name) when is_atom(rel_name) do
    rel_name
    |> Atom.to_string()
    |> format_relationship()
  end

  defp format_relationship("rel_" <> rel_name) do
    String.upcase(rel_name)
  end

  defp format_properties(rel_props) do
    Enum.map(rel_props, fn {prop, _} ->
      "#{stringify_field(prop)}: {#{stringify_field(prop)}}"
    end)
    |> Enum.join(", ")
  end

  @spec stringify_field(atom) :: String.t()
  defp stringify_field(:id), do: stringify_field(:nodeId)
  defp stringify_field(field), do: field |> Atom.to_string()
end
