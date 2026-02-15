const CrossChart = {
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

    const rawVehicle = this.el.dataset.vehicle
    const rawInstrument = this.el.dataset.instrument
    if (!rawVehicle || !rawInstrument) return

    let vehicleData, instrumentData
    try {
      vehicleData = JSON.parse(rawVehicle)
      instrumentData = JSON.parse(rawInstrument)
    } catch {
      return
    }

    if (vehicleData.length === 0 && instrumentData.length === 0) return

    const vehicleLabel = this.el.dataset.vehicleLabel || "Vehicle"
    const instrumentLabel = this.el.dataset.instrumentLabel || "Instrument"

    // Sort by time ascending
    vehicleData.sort((a, b) => new Date(a.time) - new Date(b.time))
    instrumentData.sort((a, b) => new Date(a.time) - new Date(b.time))

    // Build unified label set from both series
    const allTimes = new Set()
    vehicleData.forEach(d => allTimes.add(new Date(d.time).toLocaleDateString()))
    instrumentData.forEach(d => allTimes.add(new Date(d.time).toLocaleDateString()))
    const labels = [...allTimes].sort((a, b) => new Date(a) - new Date(b))

    // Map data to label positions
    const vehicleMap = new Map()
    vehicleData.forEach(d => vehicleMap.set(new Date(d.time).toLocaleDateString(), d.price))
    const instrumentMap = new Map()
    instrumentData.forEach(d => instrumentMap.set(new Date(d.time).toLocaleDateString(), d.price))

    const vehiclePrices = labels.map(l => vehicleMap.get(l) ?? null)
    const instrumentPrices = labels.map(l => instrumentMap.get(l) ?? null)

    if (this.chart) {
      this.chart.data.labels = labels
      this.chart.data.datasets[0].data = vehiclePrices
      this.chart.data.datasets[1].data = instrumentPrices
      this.chart.update("none")
      return
    }

    this.chart = new Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: [
          {
            label: vehicleLabel,
            data: vehiclePrices,
            borderColor: "rgb(59, 130, 246)",
            backgroundColor: "rgba(59, 130, 246, 0.1)",
            fill: false,
            tension: 0.3,
            pointRadius: 2,
            pointHoverRadius: 5,
            yAxisID: "y-vehicle",
            spanGaps: true,
          },
          {
            label: instrumentLabel,
            data: instrumentPrices,
            borderColor: "rgb(249, 115, 22)",
            backgroundColor: "rgba(249, 115, 22, 0.1)",
            fill: false,
            tension: 0.3,
            pointRadius: 2,
            pointHoverRadius: 5,
            yAxisID: "y-instrument",
            spanGaps: true,
          }
        ]
      },
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
          "y-vehicle": {
            type: "linear",
            position: "left",
            title: {
              display: true,
              text: vehicleLabel + " ($)",
              color: "rgb(59, 130, 246)",
            },
            ticks: {
              color: "rgb(59, 130, 246)",
              callback: (v) => `$${v.toLocaleString()}`
            },
            grid: {
              drawOnChartArea: true,
            }
          },
          "y-instrument": {
            type: "linear",
            position: "right",
            title: {
              display: true,
              text: instrumentLabel + " ($)",
              color: "rgb(249, 115, 22)",
            },
            ticks: {
              color: "rgb(249, 115, 22)",
              callback: (v) => `$${v.toLocaleString()}`
            },
            grid: {
              drawOnChartArea: false,
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

export { CrossChart }
