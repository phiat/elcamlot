const COLORS = [
  { border: "rgb(59, 130, 246)",  bg: "rgba(59, 130, 246, 0.1)"  },  // blue
  { border: "rgb(249, 115, 22)", bg: "rgba(249, 115, 22, 0.1)" },  // orange
  { border: "rgb(16, 185, 129)", bg: "rgba(16, 185, 129, 0.1)" },  // emerald
  { border: "rgb(239, 68, 68)",  bg: "rgba(239, 68, 68, 0.1)"  },  // red
]

const CompareChart = {
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

    const raw = this.el.dataset.datasets
    if (!raw) return

    let vehicleDatasets
    try {
      vehicleDatasets = JSON.parse(raw)
    } catch {
      return
    }

    if (vehicleDatasets.length === 0) return

    // Build unified time labels from all vehicles
    const allTimes = new Set()
    vehicleDatasets.forEach(vd => {
      vd.data.forEach(d => allTimes.add(new Date(d.time).toLocaleDateString()))
    })
    const labels = [...allTimes].sort((a, b) => new Date(a) - new Date(b))

    // Build Chart.js datasets
    const datasets = vehicleDatasets.map((vd, idx) => {
      const priceMap = new Map()
      vd.data.forEach(d => priceMap.set(new Date(d.time).toLocaleDateString(), d.price))

      const color = COLORS[idx % COLORS.length]

      return {
        label: vd.label,
        data: labels.map(l => priceMap.get(l) ?? null),
        borderColor: color.border,
        backgroundColor: color.bg,
        fill: false,
        tension: 0.3,
        pointRadius: 2,
        pointHoverRadius: 5,
        spanGaps: true,
      }
    })

    if (this.chart) {
      this.chart.data.labels = labels
      this.chart.data.datasets = datasets
      this.chart.update("none")
      return
    }

    this.chart = new Chart(canvas, {
      type: "line",
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: "index",
          intersect: false,
        },
        plugins: {
          legend: {
            display: true,
            position: "top",
          },
          tooltip: {
            callbacks: {
              label: (ctx) => {
                const val = ctx.parsed.y
                if (val == null) return null
                return `${ctx.dataset.label}: $${val.toLocaleString()}`
              }
            }
          }
        },
        scales: {
          y: {
            title: {
              display: true,
              text: "Price ($)",
            },
            ticks: {
              callback: (v) => `$${v.toLocaleString()}`
            }
          },
          x: {
            ticks: { maxTicksLimit: 10 }
          }
        }
      }
    })
  }
}

export { CompareChart }
