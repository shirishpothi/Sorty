'use client'

import { useEffect, useRef } from 'react'

type CollapseTarget = {
  x: number
  y: number
}

type FileIconFieldProps = {
  collapseTarget: CollapseTarget | null
  collapsing: boolean
  obstacleSelector?: string
}

type Particle = {
  x: number
  y: number
  vx: number
  vy: number
  size: number
  baseSize: number
  phase: number
  color: string
  kind: 'doc' | 'image' | 'folder'
  rotation: number
  collapseStartX: number
  collapseStartY: number
  collapseDelay: number
  collapseOrbit: number
}

const COLORS = ['#60a5fa', '#93c5fd', '#f8fafc', '#38bdf8', '#a78bfa']
const FILE_COUNT = 58
const BOUNCE_PADDING = 12

type Obstacle = {
  left: number
  right: number
  top: number
  bottom: number
}

function createParticle(): Particle {
  const angle = Math.random() * Math.PI * 2

  const size = 0.72 + Math.random() * 0.75

  return {
    x: Math.random(),
    y: Math.random(),
    vx: Math.cos(angle) * (0.00008 + Math.random() * 0.00018),
    vy: Math.sin(angle) * (0.00006 + Math.random() * 0.00014),
    size,
    baseSize: size,
    phase: Math.random() * Math.PI * 2,
    color: COLORS[Math.floor(Math.random() * COLORS.length)],
    kind:
      Math.random() < 0.18
        ? 'folder'
        : Math.random() < 0.42
          ? 'image'
          : 'doc',
    rotation: (Math.random() - 0.5) * 0.28,
    collapseStartX: 0,
    collapseStartY: 0,
    collapseDelay: Math.random() * 110,
    collapseOrbit: 0.035 + Math.random() * 0.09,
  }
}

function clamp(value: number, min = 0, max = 1) {
  return Math.min(max, Math.max(min, value))
}

function easeOutBack(value: number) {
  const c1 = 1.70158
  const c3 = c1 + 1

  return 1 + c3 * Math.pow(value - 1, 3) + c1 * Math.pow(value - 1, 2)
}

function easeInOutCubic(value: number) {
  return value < 0.5
    ? 4 * value * value * value
    : 1 - Math.pow(-2 * value + 2, 3) / 2
}

function measureObstacles(selector?: string): Obstacle[] {
  if (!selector) {
    return []
  }

  return Array.from(document.querySelectorAll<HTMLElement>(selector)).map(
    (element) => {
      const bounds = element.getBoundingClientRect()

      return {
        left: bounds.left - BOUNCE_PADDING,
        right: bounds.right + BOUNCE_PADDING,
        top: bounds.top - BOUNCE_PADDING,
        bottom: bounds.bottom + BOUNCE_PADDING,
      }
    },
  )
}

function bounceOffObstacles(
  particle: Particle,
  obstacles: Obstacle[],
  width: number,
  height: number,
) {
  const x = particle.x * width
  const y = particle.y * height
  const radius = 14 * particle.size

  for (const obstacle of obstacles) {
    const closestX = clamp(x, obstacle.left, obstacle.right)
    const closestY = clamp(y, obstacle.top, obstacle.bottom)
    const dx = x - closestX
    const dy = y - closestY
    const distance = Math.hypot(dx, dy)

    if (distance > radius) {
      continue
    }

    let overlap = radius - distance + 1
    let normalX = distance > 0 ? dx / distance : 0
    let normalY = distance > 0 ? dy / distance : -1

    if (distance === 0) {
      const gaps = [
        { nx: -1, ny: 0, value: Math.abs(x - obstacle.left) },
        { nx: 1, ny: 0, value: Math.abs(obstacle.right - x) },
        { nx: 0, ny: -1, value: Math.abs(y - obstacle.top) },
        { nx: 0, ny: 1, value: Math.abs(obstacle.bottom - y) },
      ].sort((a, b) => a.value - b.value)

      normalX = gaps[0].nx
      normalY = gaps[0].ny
      overlap = gaps[0].value + radius + 1
    }

    particle.x += (normalX * overlap) / Math.max(width, 1)
    particle.y += (normalY * overlap) / Math.max(height, 1)

    const dot = particle.vx * normalX + particle.vy * normalY
    if (dot < 0) {
      particle.vx = (particle.vx - 2 * dot * normalX) * 1.18
      particle.vy = (particle.vy - 2 * dot * normalY) * 1.18
    } else {
      particle.vx += normalX * 0.00018
      particle.vy += normalY * 0.00018
    }

    particle.vx = clamp(particle.vx, -0.001, 0.001)
    particle.vy = clamp(particle.vy, -0.001, 0.001)
    particle.rotation += normalX * 0.12 + normalY * 0.08
    return
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
  obstacleSelector,
}: FileIconFieldProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const particlesRef = useRef<Particle[]>([])
  const targetRef = useRef(collapseTarget)
  const collapsingRef = useRef(collapsing)
  const collapseStartedAtRef = useRef<number | null>(null)
  const obstaclesRef = useRef<Obstacle[]>([])

  useEffect(() => {
    targetRef.current = collapseTarget
  }, [collapseTarget])

  useEffect(() => {
    if (collapsing && !collapsingRef.current) {
      collapseStartedAtRef.current = performance.now()
      particlesRef.current = particlesRef.current.map((particle) => ({
        ...particle,
        collapseStartX: particle.x,
        collapseStartY: particle.y,
      }))
    }

    if (!collapsing) {
      collapseStartedAtRef.current = null
    }

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
      obstaclesRef.current = measureObstacles(obstacleSelector)
    }

    const render = () => {
      tick += 1
      ctx.clearRect(0, 0, width, height)
      const now = performance.now()

      for (const particle of particlesRef.current) {
        if (collapsingRef.current && targetRef.current) {
          const targetX = targetRef.current.x / Math.max(width, 1)
          const targetY = targetRef.current.y / Math.max(height, 1)
          const elapsed = now - (collapseStartedAtRef.current ?? now)
          const rawProgress = clamp((elapsed - particle.collapseDelay) / 430)
          const pull = easeOutBack(rawProgress)
          const fade = easeInOutCubic(rawProgress)
          const orbitAngle = particle.phase + rawProgress * Math.PI * 5.4
          const orbit = particle.collapseOrbit * Math.pow(1 - rawProgress, 1.4)
          const distanceKick = Math.sin(rawProgress * Math.PI) * 0.022

          particle.x =
            particle.collapseStartX +
            (targetX - particle.collapseStartX) * pull +
            Math.cos(orbitAngle) * (orbit + distanceKick)
          particle.y =
            particle.collapseStartY +
            (targetY - particle.collapseStartY) * pull +
            Math.sin(orbitAngle) * (orbit + distanceKick)
          particle.size = particle.baseSize * (1 - fade * 0.78)
          particle.rotation += 0.16 + rawProgress * 0.08
        } else {
          particle.x +=
            particle.vx + Math.sin(tick * 0.01 + particle.phase) * 0.0001
          particle.y +=
            particle.vy + Math.cos(tick * 0.012 + particle.phase) * 0.00008
          bounceOffObstacles(
            particle,
            obstaclesRef.current,
            width,
            height,
          )
        }

        if (!collapsingRef.current) {
          if (particle.x < -0.08) particle.x = 1.08
          if (particle.x > 1.08) particle.x = -0.08
          if (particle.y < -0.08) particle.y = 1.08
          if (particle.y > 1.08) particle.y = -0.08
        }

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
