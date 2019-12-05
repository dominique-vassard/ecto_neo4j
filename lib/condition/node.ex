defmodule Ecto.Adapters.Neo4j.Condition.Node do
  alias Ecto.Adapters.Neo4j.Condition

  @type clauses :: %{
          where: nil | Condition.t(),
          params: map()
        }

  @spec format(Condition.t(), Condition.clauses()) :: Condition.clauses()
  def format(condition, clauses \\ %{where: nil, params: %{}})

  def format(
        %Condition{
          operator: operator,
          source: source,
          field: field,
          value: value,
          conditions: [],
          join_operator: join_operator
        },
        clauses
      ) do
    bound_name = define_bound_name(source, field, clauses.params)

    condition = %Condition{
      source: source,
      field: field,
      operator: operator,
      value: bound_name,
      join_operator: join_operator
    }

    param = Map.put(%{}, String.to_atom(bound_name), value)

    %{
      clauses
      | where: Condition.join_conditions(condition, clauses.where),
        params: Map.merge(clauses.params, param)
    }
  end

  def format(%Condition{operator: operator, conditions: [condition1, condition2]}, clauses) do
    c1 = format(condition1, %{where: nil, params: clauses.params})
    c2 = format(condition2, %{where: nil, params: c1.params})

    condition =
      Condition.join_conditions(c1.where, c2.where, operator)
      |> Condition.join_conditions(clauses.where)

    %{
      clauses
      | where: condition,
        params: c2.params
    }
  end

  def format(%Condition{conditions: condition} = top_cond, clauses) do
    formated_cond = format(condition)

    %{
      clauses
      | where: Map.put(top_cond, :conditions, formated_cond.where),
        params: Map.merge(clauses.params, formated_cond.params)
    }
  end

  defp define_bound_name(source, field, params) do
    wanted_bound_name = source <> "_" <> Atom.to_string(field)

    nb_found =
      params
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.filter(fn key ->
        Regex.match?(~r/^(#{wanted_bound_name}|#{wanted_bound_name}[0-9]+)$/, key)
      end)
      |> Enum.count()

    case nb_found > 0 do
      true ->
        wanted_bound_name <> "_" <> Integer.to_string(nb_found + 1)

      false ->
        wanted_bound_name
    end
  end
end
