import { test, expect } from '@playwright/test'

test.describe('Search flow', () => {
  test('searching "serenity" navigates to word detail page with Urdu translation', async ({ page }) => {
    await page.goto('/')

    // Find and fill the search bar
    const searchInput = page.getByRole('textbox', { name: /search/i })
    await searchInput.fill('serenity')

    // Wait for autocomplete dropdown (debounce + API call)
    const dropdown = page.locator('[data-testid="search-dropdown"], [role="listbox"]')
    await dropdown.waitFor({ state: 'visible', timeout: 5000 })

    // Click the first result or press Enter to navigate
    const firstResult = dropdown.locator('[role="option"], li').first()
    await firstResult.click()

    // Should land on /word/serenity (or normalized variant)
    await expect(page).toHaveURL(/\/word\/serenity/i)

    // English word heading is visible
    await expect(page.getByRole('heading', { name: /serenity/i })).toBeVisible()

    // Urdu translation in RTL Nastaliq script is rendered
    const urduSpan = page.locator('[lang="ur"], [dir="rtl"]').first()
    await expect(urduSpan).toBeVisible()
    await expect(urduSpan).not.toBeEmpty()
  })

  test('pressing Enter in search bar navigates directly to word page', async ({ page }) => {
    await page.goto('/')

    const searchInput = page.getByRole('textbox', { name: /search/i })
    await searchInput.fill('harmony')
    await searchInput.press('Enter')

    await expect(page).toHaveURL(/\/word\/harmony/i, { timeout: 10000 })
    await expect(page.getByRole('heading', { name: /harmony/i })).toBeVisible()
  })

  test('autocomplete does not fire for single character input', async ({ page }) => {
    await page.goto('/')

    const searchInput = page.getByRole('textbox', { name: /search/i })
    await searchInput.fill('s')

    // Dropdown should NOT appear
    await page.waitForTimeout(500) // longer than debounce
    const dropdown = page.locator('[data-testid="search-dropdown"], [role="listbox"]')
    await expect(dropdown).not.toBeVisible()
  })
})
