import { slug } from './slug'

test('keeper', () => {
  expect(slug('Ab')).toBe('ab')
})
