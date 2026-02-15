const DealScoreChart = {
  mounted() {
    this.initChart()
  },

  updated() {
    this.initChart()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  },

  initChart() {
    if (!window.Chart) {
      console.warn("Chart.js not loaded yet")
      return
    }

    const canvas = this.el.querySelector("canvas")
    if (!canvas) return

    const raw = this.el.dataset.scores
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    if (data.length === 0) return

    // Sort by computed_at ascending
    data.sort((a, b) => new Date(a.computed_at) - new Date(b.computed_at))

    const labels = data.map(d => new Date(d.computed_at).toLocaleDateString())
    const scores = data.map(d => d.score)

    if (this.chart) {
      this.chart.data.labels = labels
      this.chart.data.datasets[0].data = scores
      this.chart.update("none")
      return
    }

    // Color the line based on score ranges
    const gradient = canvas.getContext("2d").createLinearGradient(0, canvas.height, 0, 0)
    gradient.addColorStop(0, "rgba(239, 68, 68, 0.8)")   // red at bottom (low score)
    gradient.addColorStop(0.5, "rgba(234, 179, 8, 0.8)")  // yellow in middle
    gradient.addColorStop(1, "rgba(34, 197, 94, 0.8)")    // green at top (high score)

    this.chart = new Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Deal Score",
          data: scores,
          borderColor: "rgb(139, 92, 246)",
          backgroundColor: "rgba(139, 92, 246, 0.1)",
          fill: true,
          tension: 0.3,
          pointRadius: 3,
          pointHoverRadius: 6,
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => `Score: ${ctx.parsed.y.toFixed(1)}`
            }
          }
        },
        scales: {
          y: {
            min: 0,
            max: 100,
            ticks: {
              callback: (v) => `${v}`
            }
          },
          x: {
            ticks: { maxTicksLimit: 8 }
          }
        }
      }
    })
  }
}

export { DealScoreChart }
