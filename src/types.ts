export type Borrower = {
  id: string; full_name: string; phone: string | null; email: string | null
  address: string | null; notes: string; created_at: string
}
export type Loan = {
  id: string; borrower_id: string; amount: number; issued_at: string; due_date: string | null
  loan_type: string; interest_rate: number; status: 'active' | 'paid' | 'overdue' | 'cancelled'
  notes: string; archived_at: string | null; created_at: string
  borrower?: Borrower
}
export type Payment = {
  id: string; loan_id: string; amount: number; paid_at: string; method: string; notes: string; created_at: string
}
export type Task = {
  id: string; title: string; description: string; due_at: string | null
  priority: 'low' | 'medium' | 'high'; status: 'pending' | 'in_progress' | 'complete'
  recurring_task_id: string | null
}
export type Reminder = { id: string; loan_id: string; action: string; note: string; contacted_at: string }
