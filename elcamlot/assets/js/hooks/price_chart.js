const PriceChart = {
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

    const raw = this.el.dataset.snapshots
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    if (data.length === 0) return

    // Sort by time ascending
    data.sort((a, b) => new Date(a.time) - new Date(b.time))

    const labels = data.map(d => new Date(d.time).toLocaleDateString())
    const prices = data.map(d => d.price)

    if (this.chart) {
      this.chart.data.labels = labels
      this.chart.data.datasets[0].data = prices
      this.chart.update("none")
      return
    }

    this.chart = new Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Price ($)",
          data: prices,
          borderColor: "rgb(59, 130, 246)",
          backgroundColor: "rgba(59, 130, 246, 0.1)",
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
              label: (ctx) => `$${ctx.parsed.y.toLocaleString()}`
            }
          }
        },
        scales: {
          y: {
            ticks: {
              callback: (v) => `$${(v).toLocaleString()}`
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

export { PriceChart }
