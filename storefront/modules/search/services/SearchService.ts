import { ProductSearchSuggestions } from '../models/ProductSearchSuggestions';
import { SearchParams } from '../models/SearchParams';
import { SearchProductResponse } from '../models/SearchProductResponse';
import apiClientService from '@/common/services/ApiClientService';

export async function getSuggestions(keyword: string): Promise<ProductSearchSuggestions> {
  const response = await apiClientService.get(
    `/api/search/storefront/search_suggest?keyword=${encodeURIComponent(keyword)}`
  );
  if (response.status >= 200 && response.status < 300) {
    return await response.json();
  }

  throw new Error(response.statusText);
}

export async function searchProducts(params: SearchParams): Promise<SearchProductResponse> {
  const queryParams = new URLSearchParams({
    keyword: params.keyword,
  });
  if (params.category) {
    queryParams.set('category', params.category);
  }
  if (params.brand) {
    queryParams.set('brand', params.brand);
  }
  if (params.attribute) {
    queryParams.set('attribute', params.attribute);
  }
  if (params.minPrice) {
    queryParams.set('minPrice', params.minPrice.toString());
  }
  if (params.maxPrice) {
    queryParams.set('maxPrice', params.maxPrice.toString());
  }
  if (params.sortType) {
    queryParams.set('sortType', params.sortType);
  }
  if (params.page) {
    queryParams.set('page', params.page.toString());
  }
  if (params.pageSize) {
    queryParams.set('size', params.pageSize.toString());
  }
  const url = `/api/search/storefront/catalog-search?${queryParams.toString()}`;
  const response = await apiClientService.get(url);
  if (response.status >= 200 && response.status < 300) {
    return await response.json();
  }
  throw new Error(response.statusText);
}
