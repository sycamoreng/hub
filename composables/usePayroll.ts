export interface PayrollEmployeeInput {
  basic: number
  housing: number
  transport: number
  utility: number
  meal: number
  leave_allowance: number
  other_earnings: number
  bonus: number
  nhf_enabled: boolean
}

export interface PayrollSettings {
  pension_employee_rate: number
  pension_employer_rate: number
  nhf_rate: number
  nhis_rate: number
  nhis_enabled: boolean
}

export interface PayrollBreakdown {
  gross: number
  pension_employee: number
  pension_employer: number
  nhf: number
  nhis: number
  cra: number
  taxable_income: number
  paye: number
  net: number
}

// PAYE bands per Finance Act 2020 (annual, NGN)
const PAYE_BANDS: { limit: number; rate: number }[] = [
  { limit: 300_000, rate: 0.07 },
  { limit: 300_000, rate: 0.11 },
  { limit: 500_000, rate: 0.15 },
  { limit: 500_000, rate: 0.19 },
  { limit: 1_600_000, rate: 0.21 },
  { limit: Infinity, rate: 0.24 }
]

function round2(n: number) {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

function paye(annualTaxable: number) {
  let remaining = Math.max(0, annualTaxable)
  let tax = 0
  for (const band of PAYE_BANDS) {
    if (remaining <= 0) break
    const slice = Math.min(remaining, band.limit)
    tax += slice * band.rate
    remaining -= slice
  }
  return tax
}

export function computePayroll(emp: PayrollEmployeeInput, settings: PayrollSettings): PayrollBreakdown {
  const earnings =
    emp.basic + emp.housing + emp.transport + emp.utility +
    emp.meal + emp.leave_allowance + emp.other_earnings + emp.bonus

  const gross = earnings

  // Pension base per PRA 2014: basic + housing + transport
  const pensionableBase = emp.basic + emp.housing + emp.transport
  const pension_employee = pensionableBase * settings.pension_employee_rate
  const pension_employer = pensionableBase * settings.pension_employer_rate

  const nhf = emp.nhf_enabled ? emp.basic * settings.nhf_rate : 0
  const nhis = settings.nhis_enabled ? emp.basic * settings.nhis_rate : 0

  // Consolidated Relief Allowance: higher of (200,000 annual or 1% of gross annual) + 20% of gross annual
  const annualGross = gross * 12
  const craFixed = Math.max(200_000, annualGross * 0.01)
  const craAnnual = craFixed + annualGross * 0.20
  const cra = craAnnual / 12

  const deductibles_annual = (pension_employee + nhf + nhis) * 12
  const taxable_annual = Math.max(0, annualGross - craAnnual - deductibles_annual)
  const paye_annual = paye(taxable_annual)
  const paye_monthly = paye_annual / 12

  const taxable_income = taxable_annual / 12

  const net = gross - pension_employee - nhf - nhis - paye_monthly

  return {
    gross: round2(gross),
    pension_employee: round2(pension_employee),
    pension_employer: round2(pension_employer),
    nhf: round2(nhf),
    nhis: round2(nhis),
    cra: round2(cra),
    taxable_income: round2(taxable_income),
    paye: round2(paye_monthly),
    net: round2(net)
  }
}

export function formatNaira(n: number | null | undefined) {
  const v = Number(n || 0)
  return '\u20A6' + v.toLocaleString('en-NG', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export const MONTH_NAMES = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December'
]
