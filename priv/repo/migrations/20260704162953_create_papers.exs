defmodule DoiDayo.Repo.Migrations.CreatePapers do
  use Ecto.Migration

  def change do
    create table(:papers) do
      add :channel_id, :string, null: false
      add :doi, :string, null: false
      # タイトルが 255 文字を超えることがあるため :text。
      add :title, :text
      add :year, :integer
      add :registered_by, :string, null: false

      timestamps()
    end

    create unique_index(:papers, [:channel_id, :doi])
  end
end
