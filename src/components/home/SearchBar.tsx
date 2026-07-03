import { IconSearch } from '../icons'

interface Props {
  value: string
  onChange: (v: string) => void
}

export default function SearchBar({ value, onChange }: Props) {
  return (
    <div className="px-4 pt-3">
      <label className="hm-pill flex items-center gap-2.5 h-11 px-4 focus-within:ring-2 focus-within:ring-ink/10">
        <IconSearch size={16} className="text-fog shrink-0" />
        <input
          type="search"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="Search moods, tools, presets"
          className="w-full bg-transparent text-[14px] placeholder:text-fog outline-none"
          aria-label="Search moods, tools and presets"
        />
        {value && (
          <button
            onClick={() => onChange('')}
            className="text-[12px] font-semibold text-fog hover:text-ink shrink-0"
            aria-label="Clear search"
          >
            Clear
          </button>
        )}
      </label>
    </div>
  )
}
