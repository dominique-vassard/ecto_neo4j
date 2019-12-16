defmodule Ecto.Adapters.Neo4j.Condition.Relationship do
  alias Ecto.Adapters.Neo4j.Condition
  alias Ecto.Adapters.Neo4j.Query.{NodeExpr, RelationshipExpr}

  @type clauses :: %{
          match: [],
          where: nil | Condition.t(),
          params: map()
        }

  @spec format(Condition.t()) :: clauses
  def format(condition, clauses \\ %{match: [], where: nil, params: %{}})

  def format(nil, _) do
    nil
  end

  def format(%{operator: :or}, _) do
    raise "OR is not supported in joins!"
  end

  def format(%{source: end_variable, field: field, operator: :is_nil}, clauses)
      when not is_nil(field) do
    relationship = %RelationshipExpr{
      start: %NodeExpr{
        index: 0,
        variable: "n_0"
      },
      end: %NodeExpr{
        variable: end_variable
      },
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

  def format(
        %{source: end_variable, field: field, operator: :==, value: value},
        clauses
      )
      when not is_nil(field) do
    rel_variable = Atom.to_string(field) <> "_" <> end_variable

    relationship = %Ecto.Adapters.Neo4j.Query.RelationshipExpr{
      variable: rel_variable,
      start: %NodeExpr{
        index: 0,
        variable: "n_0"
      },
      end: %NodeExpr{
        variable: end_variable
      },
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

  def format(
        %{operator: operator, conditions: [condition1, condition2]},
        clauses
      ) do
    c1 = format(condition1)
    c2 = format(condition2)

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

  def format(%{source: end_variable, field: nil}, clauses) do
    relationship = %Ecto.Adapters.Neo4j.Query.RelationshipExpr{
      variable: "rel_" <> end_variable,
      start: %NodeExpr{
        index: 0,
        variable: "n_0"
      },
      end: %NodeExpr{
        variable: end_variable
      },
      type: nil
    }

    %{
      clauses
      | match: clauses.match ++ [relationship]
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

          nil ->
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
