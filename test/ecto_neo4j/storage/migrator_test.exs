defmodule EctoNeo4j.Storage.MigratorTest do
  use ExUnit.Case, async: true

  defmodule MigrationTest.Create do
    use Ecto.Migration

    def up do
      create(table(:add_col_if_not_exists_migration))

      alter table(:add_col_if_not_exists_migration) do
        add_if_not_exists(:value, :integer)
        add_if_not_exists(:to_be_added, :integer)
      end
    end
  end

  alias Ecto.Integration.TestRepo
  alias Ecto.Migrator

  test "test create" do
    Migrator.up(TestRepo, 1, MigrationTest.Create)
  end
end
