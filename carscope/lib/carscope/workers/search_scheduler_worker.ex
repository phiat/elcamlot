defmodule Carscope.Workers.SearchSchedulerWorker do
  @moduledoc """
  Oban cron worker that finds due saved searches and enqueues scraper jobs.
  Runs every hour; each invocation checks which searches are due based on schedule.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger
  alias Carscope.Watchlist

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for schedule <- ["hourly", "6hr", "daily"] do
      searches = Watchlist.list_due_searches(schedule)

      Enum.each(searches, fn search ->
        %{saved_search_id: search.id}
        |> Carscope.Workers.SearchScraperWorker.new()
        |> Oban.insert()
      end)

      if searches != [] do
        Logger.info("Enqueued #{length(searches)} #{schedule} scrape jobs")
      end
    end

    :ok
  end
end
