defmodule EctoNeo4j.Adapter do
  @behaviour Ecto.Adapter

  defmacro __before_compile__(_env), do: :ok

  def ensure_all_started(_config, type) do
    {:ok, _} = Application.ensure_all_started(:bolt_sips, type)
  end

  def init(_config) do
    opts = Application.get_env(:bolt_sips, Bolt)
    {:ok, Bolt.Sips.child_spec(opts), %{}}
  end

  def checkout(_, _, fun), do: fun.()

  def dumpers(:uuid, _type), do: [&Ecto.UUID.cast/1, :string]
  def dumpers(_primitive, type), do: [type]

  def loaders(:uuid, _type), do: [&Ecto.UUID.dump/1, Ecto.UUID]
  def loaders(_primitive, type), do: [type]

  @behaviour Ecto.Adapter.Queryable
  defdelegate prepare(operation, query), to: EctoNeo4j.Behaviour.Queryable

  defdelegate execute(repo, query_meta, query_cache, sources, preprocess, opts \\ []),
    to: EctoNeo4j.Behaviour.Queryable

  defdelegate stream(adapter_meta, query_meta, query_cache, params, opts \\ []),
    to: EctoNeo4j.Behaviour.Queryable

  @behaviour Ecto.Adapter.Schema
  defdelegate autogenerate(field_type), to: EctoNeo4j.Behaviour.Schema

  defdelegate insert_all(
                adapter_meta,
                schema_meta,
                header,
                entries,
                on_conflict,
                returning,
                options
              ),
              to: EctoNeo4j.Behaviour.Schema

  defdelegate insert(adapter_meta, schema_meta, fields, on_conflict, returning, options),
    to: EctoNeo4j.Behaviour.Schema

  defdelegate update(adapter_meta, schema_meta, fields, filters, returning, options),
    to: EctoNeo4j.Behaviour.Schema

  defdelegate delete(adapter_meta, schema_meta, filters, options), to: EctoNeo4j.Behaviour.Schema

  defdelegate query(cql, params \\ %{}, opts \\ []), to: EctoNeo4j.Behaviour.Queryable
  defdelegate query!(cql, params \\ %{}, opts \\ []), to: EctoNeo4j.Behaviour.Queryable
end
