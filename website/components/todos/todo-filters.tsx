'use client'

import { Button } from '@/components/ui/button'

interface TodoFiltersProps {
  activeFilter: 'all' | 'active' | 'completed'
  onFilterChange: (filter: 'all' | 'active' | 'completed') => void
  totalTodos: number
  activeTodos: number
  completedTodos: number
}

export function TodoFilters({
  activeFilter,
  onFilterChange,
  totalTodos,
  activeTodos,
  completedTodos,
}: TodoFiltersProps) {
  return (
    <div className="p-0 flex flex-wrap items-center gap-2 flex-row border-none bg-transparent shadow-none mb-4">
      <Button
        variant={activeFilter === 'all' ? 'default' : 'outline'}
        onClick={() => onFilterChange('all')}
        size="sm"
      >
        All ({totalTodos})
      </Button>
      <Button
        variant={activeFilter === 'active' ? 'default' : 'outline'}
        onClick={() => onFilterChange('active')}
        size="sm"
      >
        Active ({activeTodos})
      </Button>
      <Button
        variant={activeFilter === 'completed' ? 'default' : 'outline'}
        onClick={() => onFilterChange('completed')}
        size="sm"
      >
        Completed ({completedTodos})
      </Button>
    </div>
  )
}
