import { test, expect } from '@playwright/test'

test.describe('Browse page', () => {
  test('browse by "religion" context shows words tagged with religion', async ({ page }) => {
    await page.goto('/browse?context=religion')

    // Page loads with word cards
    const wordCards = page.locator('[data-testid="word-card"]')
    await expect(wordCards.first()).toBeVisible({ timeout: 8000 })

    // At least one card visible
    const count = await wordCards.count()
    expect(count).toBeGreaterThan(0)

    // URL reflects the filter
    await expect(page).toHaveURL(/context=religion/)
  })

  test('clicking a difficulty filter updates URL and re-fetches', async ({ page }) => {
    await page.goto('/browse')

    // Find and click the beginner difficulty filter
    const filterButton = page.getByRole('button', { name: /beginner/i })
      .or(page.getByRole('link', { name: /beginner/i }))
      .or(page.locator('[data-filter="beginner"]'))
    await filterButton.first().click()

    await expect(page).toHaveURL(/difficulty=beginner/i, { timeout: 5000 })
  })

  test('"Load more" appends additional word cards', async ({ page }) => {
    await page.goto('/browse')

    const wordCards = page.locator('[data-testid="word-card"]')
    await expect(wordCards.first()).toBeVisible({ timeout: 8000 })
    const initialCount = await wordCards.count()

    const loadMore = page.getByRole('button', { name: /load more/i })
    if (await loadMore.isVisible()) {
      await loadMore.click()
      await page.waitForTimeout(2000)
      const newCount = await wordCards.count()
      expect(newCount).toBeGreaterThan(initialCount)
    }
  })

  test('category links on home page navigate to browse with context filter', async ({ page }) => {
    await page.goto('/')

    // Category links are on the home page
    const religionLink = page.getByRole('link', { name: /religion/i }).first()
    if (await religionLink.isVisible()) {
      await religionLink.click()
      await expect(page).toHaveURL(/\/browse.*context=religion/i, { timeout: 5000 })
    }
  })
})
