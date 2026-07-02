'use client'

import { useEffect, useRef } from 'react'

type CollapseTarget = {
  x: number
  y: number
}

type FileIconFieldProps = {
  collapseTarget: CollapseTarget | null
  collapsing: boolean
}

type Particle = {
  x: number
  y: number
  vx: number
  vy: number
  size: number
  phase: number
  color: string
  kind: 'doc' | 'image' | 'folder'
  rotation: number
}

const COLORS = ['#60a5fa', '#93c5fd', '#f8fafc', '#38bdf8', '#a78bfa']
const FILE_COUNT = 58

function createParticle(): Particle {
  const angle = Math.random() * Math.PI * 2

  return {
    x: Math.random(),
    y: Math.random(),
    vx: Math.cos(angle) * (0.00008 + Math.random() * 0.00018),
    vy: Math.sin(angle) * (0.00006 + Math.random() * 0.00014),
    size: 0.72 + Math.random() * 0.75,
    phase: Math.random() * Math.PI * 2,
    color: COLORS[Math.floor(Math.random() * COLORS.length)],
    kind:
      Math.random() < 0.18
        ? 'folder'
        : Math.random() < 0.42
          ? 'image'
          : 'doc',
    rotation: (Math.random() - 0.5) * 0.28,
  }
}

function drawFileIcon(
  ctx: CanvasRenderingContext2D,
  particle: Particle,
  width: number,
  height: number,
  tick: number,
) {
  const iconWidth = 18 * particle.size
  const iconHeight =
    particle.kind === 'folder' ? 14 * particle.size : 22 * particle.size
  const x = particle.x * width
  const y = particle.y * height
  const pulse = 0.52 + Math.abs(Math.sin(tick * 0.024 + particle.phase)) * 0.32

  ctx.save()
  ctx.translate(x, y)
  ctx.rotate(particle.rotation + Math.sin(tick * 0.008 + particle.phase) * 0.035)
  ctx.globalAlpha = pulse
  ctx.lineWidth = Math.max(1, particle.size)
  ctx.strokeStyle = particle.color
  ctx.fillStyle = particle.color

  if (particle.kind === 'folder') {
    const tabWidth = iconWidth * 0.42
    const tabHeight = iconHeight * 0.32

    ctx.beginPath()
    ctx.roundRect(
      -iconWidth / 2,
      -iconHeight / 2 + tabHeight * 0.35,
      iconWidth,
      iconHeight,
      3,
    )
    ctx.stroke()
    ctx.globalAlpha = pulse * 0.42
    ctx.fill()
    ctx.globalAlpha = pulse
    ctx.beginPath()
    ctx.roundRect(-iconWidth / 2 + 1, -iconHeight / 2, tabWidth, tabHeight, 2)
    ctx.stroke()
    ctx.restore()
    return
  }

  const fold = 5 * particle.size
  ctx.beginPath()
  ctx.moveTo(-iconWidth / 2, -iconHeight / 2)
  ctx.lineTo(iconWidth / 2 - fold, -iconHeight / 2)
  ctx.lineTo(iconWidth / 2, -iconHeight / 2 + fold)
  ctx.lineTo(iconWidth / 2, iconHeight / 2)
  ctx.lineTo(-iconWidth / 2, iconHeight / 2)
  ctx.closePath()
  ctx.stroke()
  ctx.globalAlpha = pulse * 0.2
  ctx.fill()
  ctx.globalAlpha = pulse
  ctx.beginPath()
  ctx.moveTo(iconWidth / 2 - fold, -iconHeight / 2)
  ctx.lineTo(iconWidth / 2 - fold, -iconHeight / 2 + fold)
  ctx.lineTo(iconWidth / 2, -iconHeight / 2 + fold)
  ctx.stroke()

  if (particle.kind === 'image') {
    ctx.beginPath()
    ctx.arc(-iconWidth * 0.18, -iconHeight * 0.1, 1.5 * particle.size, 0, Math.PI * 2)
    ctx.fill()
    ctx.beginPath()
    ctx.moveTo(-iconWidth * 0.34, iconHeight * 0.28)
    ctx.lineTo(-iconWidth * 0.05, iconHeight * 0.02)
    ctx.lineTo(iconWidth * 0.3, iconHeight * 0.3)
    ctx.stroke()
  } else {
    for (let i = 0; i < 3; i += 1) {
      const lineY = -iconHeight * 0.12 + i * 5 * particle.size
      ctx.beginPath()
      ctx.moveTo(-iconWidth * 0.28, lineY)
      ctx.lineTo(iconWidth * 0.24, lineY)
      ctx.stroke()
    }
  }

  ctx.restore()
}

export function FileIconField({
  collapseTarget,
  collapsing,
}: FileIconFieldProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const particlesRef = useRef<Particle[]>([])
  const targetRef = useRef(collapseTarget)
  const collapsingRef = useRef(collapsing)

  useEffect(() => {
    targetRef.current = collapseTarget
  }, [collapseTarget])

  useEffect(() => {
    collapsingRef.current = collapsing
  }, [collapsing])

  useEffect(() => {
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')

    if (!canvas || !ctx) {
      return
    }

    particlesRef.current = Array.from({ length: FILE_COUNT }, createParticle)

    let animationFrame = 0
    let tick = 0
    let width = 0
    let height = 0

    const resize = () => {
      const dpr = window.devicePixelRatio || 1
      width = window.innerWidth
      height = window.innerHeight
      canvas.width = Math.round(width * dpr)
      canvas.height = Math.round(height * dpr)
      canvas.style.width = `${width}px`
      canvas.style.height = `${height}px`
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    }

    const render = () => {
      tick += 1
      ctx.clearRect(0, 0, width, height)

      for (const particle of particlesRef.current) {
        if (collapsingRef.current && targetRef.current) {
          const targetX = targetRef.current.x / Math.max(width, 1)
          const targetY = targetRef.current.y / Math.max(height, 1)
          particle.x += (targetX - particle.x) * 0.085
          particle.y += (targetY - particle.y) * 0.085
          particle.size *= 0.985
        } else {
          particle.x +=
            particle.vx + Math.sin(tick * 0.01 + particle.phase) * 0.0001
          particle.y +=
            particle.vy + Math.cos(tick * 0.012 + particle.phase) * 0.00008
        }

        if (particle.x < -0.08) particle.x = 1.08
        if (particle.x > 1.08) particle.x = -0.08
        if (particle.y < -0.08) particle.y = 1.08
        if (particle.y > 1.08) particle.y = -0.08

        drawFileIcon(ctx, particle, width, height, tick)
      }

      animationFrame = requestAnimationFrame(render)
    }

    resize()
    window.addEventListener('resize', resize)
    animationFrame = requestAnimationFrame(render)

    return () => {
      window.removeEventListener('resize', resize)
      cancelAnimationFrame(animationFrame)
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      className="pointer-events-none absolute inset-0 size-full"
      aria-hidden="true"
    />
  )
}
