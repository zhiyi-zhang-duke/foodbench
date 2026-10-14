You are grading one specific property of a recipe written by an AI model. Be strict and literal. Judge only the property named below, nothing else about the recipe.

## The user's request
{prompt}

## The recipe to grade
{recipe}

## Property to check ({dimension})
{check}

## Instructions
- Reply PASS if the recipe clearly satisfies the property.
- Reply FAIL if the recipe violates it, or if the property is relevant and the recipe is silent where it should not be.
- Reply NA only if the property cannot apply to this recipe at all (for example, a searing rule when nothing is seared).
- Quote the exact line or phrase from the recipe that supports your verdict. If nothing supports it, write "no evidence".

Respond with a single JSON object and nothing else:
{{"verdict": "pass" | "fail" | "na", "evidence": "<quoted line or 'no evidence'>"}}
