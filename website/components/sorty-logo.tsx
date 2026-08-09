import Image from 'next/image'
import { cn } from '@/lib/utils'
import { sitePath } from '@/lib/site-paths'

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
        src={sitePath('/sorty-icon.webp')}
        alt=""
        width={28}
        height={28}
        className="size-7 rounded-[7px]"
        preload
      />
      {showWordmark && (
        <span className="text-[15px] font-semibold tracking-tight">Sorty</span>
      )}
    </span>
  )
}
