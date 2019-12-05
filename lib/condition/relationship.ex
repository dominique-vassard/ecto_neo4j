defmodule Ecto.Adapters.Neo4j.Condition.Relationship do
  alias Ecto.Adapters.Neo4j.Condition

  @type clauses :: %{
          match: [],
          where: nil | Condition.t(),
          params: map(),
          link_operator: :and | :or
        }

  @spec format({:and | :or, Condition.t()}) :: clauses
  def format({link_operator, condition}) do
    clauses = %{match: [], where: nil, params: %{}, link_operator: link_operator}
    do_format(condition, clauses)
  end

  @spec do_format(Condition.t(), clauses) :: clauses

  def do_format(condition, clauses \\ %{match: [], where: nil, params: %{}, link_operator: :and})

  def do_format(%{operator: :or}, _) do
    raise "OR is not supported in joins!"
  end

  def do_format(
        %{
          source: end_index,
          field: field,
          operator: :is_nil
        },
        clauses
      )
      when not is_nil(field) do
    relationship = %Ecto.Adapters.Neo4j.Query.RelationshipExpr{
      start_index: "n_0",
      end_index: "n_" <> Integer.to_string(end_index),
      type: format_relationship(field)
    }

    condition = %Condition{
      operator: :not,
      field: relationship
    }

    new_condition =
      case clauses.where do
        %Condition{} = prev_condition ->
          %Condition{
            operator: :and,
            conditions: [prev_condition, condition]
          }

        _ ->
          condition
      end

    %{clauses | where: new_condition}
  end

  def do_format(
        %{source: end_index, field: field, operator: :==, value: value},
        clauses
      )
      when not is_nil(field) do
    rel_variable = (field |> Atom.to_string()) <> inspect(end_index)

    relationship = %Ecto.Adapters.Neo4j.Query.RelationshipExpr{
      variable: rel_variable,
      start_index: "n_0",
      end_index: "n_" <> Integer.to_string(end_index),
      type: format_relationship(field)
    }

    wheres =
      value
      |> Enum.map(fn {prop, value} ->
        key = rel_variable <> "_" <> Atom.to_string(prop)

        {%Condition{
           source: rel_variable,
           field: prop,
           operator: :==,
           value: key
         }, Map.put(%{}, String.to_atom(key), value)}
      end)

    new_clauses = %{
      clauses
      | match: clauses.match ++ [relationship]
    }

    format_wheres(wheres, new_clauses)
  end

  def do_format(
        %{operator: operator, conditions: [condition1, condition2]},
        clauses
      ) do
    c1 = do_format(condition1)
    c2 = do_format(condition2)

    condition =
      Condition.join_conditions(c1.where, c2.where, operator)
      |> Condition.join_conditions(clauses.where)

    %{
      clauses
      | match: clauses.match ++ c1.match ++ c2.match,
        where: condition,
        params: clauses.params |> Map.merge(c1.params) |> Map.merge(c2.params)
    }
  end

  defp format_relationship(rel_name) when is_atom(rel_name) do
    rel_name
    |> Atom.to_string()
    |> format_relationship()
  end

  defp format_relationship("rel_" <> rel_name) do
    String.upcase(rel_name)
  end

  defp format_wheres([], clauses) do
    clauses
  end

  defp format_wheres(wheres, clauses) do
    Enum.reduce(wheres, clauses, fn {where, params}, acc ->
      n_cond =
        case acc.where do
          [] ->
            where

          condition ->
            %Condition{
              operator: :and,
              conditions: [
                condition,
                where
              ]
            }
        end

      %{
        acc
        | where: n_cond,
          params: Map.merge(acc.params, params)
      }
    end)
  end
end
