import Image from 'next/image'
import { cn } from '@/lib/utils'

export function SortyLogo({
  className,
  showWordmark = true,
}: {
  className?: string
  showWordmark?: boolean
}) {
  return (
    <span className={cn('flex items-center gap-2', className)}>
      <Image
        src="/sorty-icon.png"
        alt="Sorty"
        width={28}
        height={28}
        className="size-7 rounded-[7px]"
        priority
      />
      {showWordmark && (
        <span className="text-[15px] font-semibold tracking-tight">Sorty</span>
      )}
    </span>
  )
}
